-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- ELF file parser.
-- @module wf.internal.elf
-- @alias M

local vstruct = require("vstruct")
local M = {}

M.ELF_MAGIC = string.char(127) .. "ELF"
M.ELFCLASS32 = 1
M.ELFCLASS64 = 2
M.ELFDATA2LSB = 1
M.ELFDATA2MSB = 2
M.ET_NONE = 0
M.ET_REL = 1
M.ET_EXEC = 2
M.ET_DYN = 3
M.ET_CORE = 4
M.EM_NONE = 0
M.EM_MIPS = 8
M.SHN_UNDEF = 0
M.SHN_ABS = 0xFFF1
M.SHN_COMMON = 0xFFF2
M.SHT_NULL = 0
M.SHT_PROGBITS = 1
M.SHT_SYMTAB = 2
M.SHT_STRTAB = 3
M.SHT_RELA = 4
M.SHT_HASH = 5
M.SHT_DYNAMIC = 6
M.SHT_NOTE = 7
M.SHT_NOBITS = 8
M.SHT_REL = 9
M.SHT_SHLIB = 10
M.SHT_DYNSYM = 11
M.SHT_INIT_ARRAY = 14
M.SHT_FINI_ARRAY = 15
M.SHT_PREINIT_ARRAY = 16
M.SHT_GROUP = 17
M.SHT_SYMTAB_SHNDX = 18
M.SHF_WRITE            = 0x00000001
M.SHF_ALLOC            = 0x00000002
M.SHF_EXECINSTR        = 0x00000004
M.SHF_MERGE            = 0x00000010
M.SHF_STRINGS          = 0x00000020
M.SHF_INFO_LINK        = 0x00000040
M.SHF_LINK_ORDER       = 0x00000080
M.SHF_OS_NONCONFORMING = 0x00000100
M.SHF_GROUP            = 0x00000200
M.SHF_TLS              = 0x00000400
M.SHF_EXCLUDE          = 0x80000000
M.GRP_COMDAT = 1
M.PT_NULL = 0
M.PT_LOAD = 1
M.PT_DYNAMIC = 2
M.PT_INTERP = 3
M.PT_NOTE = 4
M.PT_SHLIB = 5
M.PT_PHDR = 6
M.PT_TLS = 7

local function get_e_w(header)
    local e, w
    if header.bitness == M.ELFCLASS32 then
        w = 4
    elseif header.bitness == M.ELFCLASS64 then
        w = 8
    else
        error("invalid elf class: " .. header.bitness)
    end
    if header.endianness == M.ELFDATA2LSB then
        e = "<"
    elseif header.endianness == M.ELFDATA2MSB then
        e = ">"
    else
        error("invalid elf endianness: " .. header.endianness)
    end
    return e, w
end

--- Read ELF file header.
function M.parse(file, expected_bitness, expected_endianness, expected_machine)
    local header = {}
    -- ident
    local magic, bitness, endianness, cc, os_abi, os_abi_version = string.unpack(
        "<c4BBBBBxxxxxxx", file:read(16)
    )
    if magic ~= M.ELF_MAGIC then
        error("invalid elf magic")
    end
    if expected_bitness ~= nil and expected_bitness ~= bitness then
        error("invalid elf class: " .. bitness .. ", expected " .. expected_bitness)
    end
    if expected_endianness ~= nil and expected_endianness ~= endianness then
        error("invalid elf endianness: " .. endianness .. ", expected " .. expected_endianness)
    end
    header.bitness = bitness
    header.endianness = endianness
    header.os_abi = os_abi
    header.os_abi_version = os_abi_version
    local e, w = get_e_w(header)
    -- ehdr
    local ehdr_pack = e .. "I2I2I4I" .. w .. "I" .. w .. "I" .. w .. "I4I2I2I2I2I2I2"
    header.type, header.machine, header.version, header.entry,
    header.phoff, header.shoff, header.flags, header.ehsize,
    header.phentsize, header.phnum, header.shentsize, header.shnum, header.shstrndx = string.unpack(
        ehdr_pack, file:read(string.packsize(ehdr_pack))
    )
    if expected_machine ~= nil and expected_machine ~= header.machine then
        error("invalid elf machine: " .. header.machine .. ", expected " .. expected_machine)
    end
    -- phdr
    file:seek("set", header.phoff)
    header.phdr = {}
    for i=1,header.phnum do
        local phdr = {}
        if w == 8 then
            phdr.type, phdr.flags, phdr.offset, phdr.vaddr, phdr.paddr,
            phdr.filesz, phdr.memsz, phdr.align = string.unpack(
                e .. "I4I4I8I8I8I8I8I8", file:read(header.phentsize)
            )
        else
            phdr.type, phdr.offset, phdr.vaddr, phdr.paddr, phdr.filesz,
            phdr.memsz, phdr.flags, phdr.align = string.unpack(
                e .. "I4I4I4I4I4I4I4I4", file:read(header.phentsize)
            )
        end
        header.phdr[i] = phdr
    end
    -- shdr
    file:seek("set", header.shoff)
    header.shdr = {}
    for i=1,header.shnum do
        local shdr = {}
        if w == 8 then
            shdr.name, shdr.type, shdr.flags, shdr.addr, shdr.offset,
            shdr.size, shdr.link, shdr.info, shdr.addralign, shdr.entsize = string.unpack(
                e .. "I4I4I8I8I8I8I4I4I8I8", file:read(header.shentsize)
            )
        else
            shdr.name, shdr.type, shdr.flags, shdr.addr, shdr.offset,
            shdr.size, shdr.link, shdr.info, shdr.addralign, shdr.entsize = string.unpack(
                e .. "I4I4I4I4I4I4I4I4I4I4", file:read(header.shentsize)
            )
        end
        header.shdr[i] = shdr
    end
    -- TODO: process strtab/symtab

    return header
end

return M
