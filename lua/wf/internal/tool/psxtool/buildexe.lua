-- SPDX-License-Identifier: Zlib
-- SPDX-FileContributor: Ben "GreaseMonkey" Russell, 2017, 2018, 2019
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2019, 2023

local path = require('pl.path')
local toml = require('wf.internal.toml')
local wfelf = require('wf.internal.elf')
local wfmath = require('wf.internal.math')
local wfpsx = require('wf.internal.platform.psx')
local log = require('wf.internal.log')

local function mkpsexe_run(args, linker_args)
    log.verbose = log.verbose or args.verbose

    local config = toml.decodeFromFile(args.config or "wfconfig.toml")
    local elf_file <close> = io.open(args.input, "rb")
    local elf_file_root, elf_file_ext = path.splitext(args.input)
    local elf = wfelf.ELF(elf_file, 0, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_MIPS)

    log.info(string.format("Entry point: %08X", elf.entry))
    local target_text_start = 0xFFFFFFFF
    local target_text_end = 0x00000000
    for i=1,#elf.phdr do
        local phdr = elf.phdr[i]
		log.info(string.format("PHdr %05u: %08X %08X %08X %08X %08X %08X %08X align %X"
            , i-1
            , phdr.type
            , phdr.offset
            , phdr.vaddr
            , phdr.paddr
            , phdr.filesz
            , phdr.memsz
            , phdr.flags
            , phdr.align
        ))

        if phdr.type == wfelf.PT_LOAD and phdr.filesz > 0 then
            target_text_start = math.min(target_text_start, phdr.vaddr)
            target_text_end = math.max(target_text_end, phdr.vaddr + phdr.filesz - 1)
        end
    end

    if target_text_start > target_text_end then
        log.fatal("could not find code/data in ELF")
    end
    if target_text_start < 0x80010000 then
        log.fatal("code/data starts too early")
    end
    if target_text_end >= 0x80200000 then
        log.fatal("code/data ends too late")
    end
    if (target_text_start & 0x7FF) ~= 0 then
        log.fatal("code/data not aligned to 2 KB")
    end

    local target_text_length = wfmath.pad_alignment_to(target_text_end - target_text_start + 1, 2048)
    local exe_file <close> = io.open(args.output or (elf_file_root .. ".exe"), "wb")
    exe_file:write(wfpsx.create_exe_header({
        ["pc"] = elf.entry,
        ["load_address"] = target_text_start,
        ["load_length"] = target_text_length,
        ["marker"] = "Wonderful toolchain"
    }))
    local blank_sector = string.char(0):rep(2048)
    for i=1,target_text_length,2048 do
        exe_file:write(blank_sector)
    end
    for i=1,#elf.phdr do
        local phdr = elf.phdr[i]
        if phdr.type == wfelf.PT_LOAD and phdr.filesz > 0 then
            local exe_addr = phdr.vaddr - target_text_start
            if exe_addr < 0 or (exe_addr + phdr.filesz) > target_text_length then
                log.fatal("exe phdr section out of range: " .. i)
            end
            elf_file:seek("set", phdr.offset)
            exe_file:seek("set", 2048 + exe_addr)
            exe_file:write(elf_file:read(phdr.filesz))
        end
    end
end

return {
    ["arguments"] = [[
[args...] <input>: convert an ELF file to a PS-EXE
  -c,--config   (optional string)  Configuration file name;
                                   wfconfig.toml is used by default.
  -o,--output   (string)           Output PS-EXE file name.
  -v,--verbose                     Enable verbose logging.
  <input>       (string)           Input ELF file.
]],
    ["description"] = "convert an ELF file to a PS-EXE",
    ["run"] = mkpsexe_run
}
