-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- ELF file parser.

local class = require('pl.class')
local log = require('wf.internal.log')

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
M.EM_386 = 3
M.EM_MIPS = 8
M.EM_ARM = 40
M.SHN_UNDEF = 0
M.SHN_ABS = 0xFFF1
M.SHN_COMMON = 0xFFF2
M.SHN_XINDEX = 0xFFFF
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
M.SHF_GNU_RETAIN       = 0x00200000
M.SHF_EXCLUDE          = 0x80000000
M.STT_NOTYPE = 0
M.STT_OBJECT = 1
M.STT_FUNC = 2
M.STT_SECTION = 3
M.STT_FILE = 4
M.STT_COMMON = 5
M.GRP_COMDAT = 1
M.PT_NULL = 0
M.PT_LOAD = 1
M.PT_DYNAMIC = 2
M.PT_INTERP = 3
M.PT_NOTE = 4
M.PT_SHLIB = 5
M.PT_PHDR = 6
M.PT_TLS = 7
M.R_386_NONE = 0
M.R_386_32 = 1
M.R_386_16 = 20
M.R_386_PC16 = 21
M.R_386_SEG16 = 45
M.R_386_SUB16 = 46
M.R_386_SUB32 = 47
M.R_386_SEGRELATIVE = 48
M.R_386_OZSEG16 = 80
M.R_386_OZRELSEG16 = 81

M.PARSE_SECTIONS = 0x1
M.PARSE_SYMBOLS = 0x2
M.PARSE_STRTABS = 0x4
M.PARSE_ALL = 0xFFFFFFFF

local ELF = class()
M.ELF = ELF

local packing_cache = {}
local function get_packing(header)
    local e, w
    local key = 1
    if header.bitness == M.ELFCLASS32 then
        w = 4
    elseif header.bitness == M.ELFCLASS64 then
        w = 8
        key = key + 2
    else
        log.fatal("invalid elf class: " .. header.bitness)
    end
    if header.endianness == M.ELFDATA2LSB then
        e = "<"
    elseif header.endianness == M.ELFDATA2MSB then
        e = ">"
        key = key + 1
    else
        log.fatal("invalid elf endianness: " .. header.endianness)
    end
    local pack = packing_cache[key]
    if pack == nil then
        pack = {}
        pack.e = e
        pack.w = w
        pack.ehdr = e .. "I2I2I4I" .. w .. "I" .. w .. "I" .. w .. "I4I2I2I2I2I2I2"
        if w == 8 then
            pack.phent = e .. "I4I4I8I8I8I8I8I8"
            pack.shent = e .. "I4I4I8I8I8I8I4I4I8I8"
            pack.sym = e .. "I4BBI2I8I8"
        else
            pack.phent = e .. "I4I4I4I4I4I4I4I4"
            pack.shent = e .. "I4I4I4I4I4I4I4I4I4I4"
            pack.sym = e .. "I4I4I4BBI2"
        end
        packing_cache[key] = pack
    end
    return pack
end

function M.read_string(file, section, offset)
    if section == nil or offset == 0 then return "" end
    
    file:seek("set", section.offset + offset)
    local s = ""

    local chunk = ""
    local chunk_size = 64
    local i = 1

    while true do
        local new_chunk = file:read(chunk_size)
        if new_chunk == nil then
            return s
        end
        chunk = chunk .. new_chunk
        while i <= #chunk do
            if string.byte(chunk, i) == 0 then
                return chunk:sub(1, i - 1)
            end
            i = i + 1
        end
    end
end

function ELF:_init(file, flags, expected_bitness, expected_endianness, expected_machine, expected_type)
    if file ~= nil then
        -- ident
        local magic, bitness, endianness, cc, os_abi, os_abi_version = string.unpack(
            "<c4BBBBBxxxxxxx", file:read(16)
        )
        if magic ~= M.ELF_MAGIC then
            log.fatal("invalid elf magic")
        end
        if expected_bitness ~= nil and expected_bitness ~= bitness then
            log.fatal("invalid elf class: " .. bitness .. ", expected " .. expected_bitness)
        end
        if expected_endianness ~= nil and expected_endianness ~= endianness then
            log.fatal("invalid elf endianness: " .. endianness .. ", expected " .. expected_endianness)
        end
        self.bitness = bitness
        self.endianness = endianness
        self.os_abi = os_abi
        self.os_abi_version = os_abi_version
        local pack = get_packing(self)

        -- ELF header
        self.type, self.machine, self.version, self.entry,
        self.phoff, self.shoff, self.flags, self.ehsize,
        self.phentsize, self.phnum, self.shentsize, self.shnum, self.shstrndx = string.unpack(
            pack.ehdr, file:read(string.packsize(pack.ehdr))
        )
        if expected_machine ~= nil and expected_machine ~= self.machine then
            log.fatal("invalid elf machine: " .. self.machine .. ", expected " .. expected_machine)
        end
        if expected_type ~= nil and expected_type ~= self.type then
            log.fatal("invalid elf type: " .. self.type .. ", expected " .. expected_type)
        end

        -- Program headers
        self.phdr = {}
        if self.phnum > 0 then
            if self.phentsize ~= string.packsize(pack.phent) then
                log.fatal("invalid program header entry size: " .. self.phentsize .. ", expected " .. string.packsize(pack.phent))
            end
            file:seek("set", self.phoff)
            for i=1,self.phnum do
                local phdr = {}
                if pack.w == 8 then
                    phdr.type, phdr.flags, phdr.offset, phdr.vaddr, phdr.paddr,
                    phdr.filesz, phdr.memsz, phdr.align = string.unpack(
                        pack.phent, file:read(self.phentsize)
                    )
                else
                    phdr.type, phdr.offset, phdr.vaddr, phdr.paddr, phdr.filesz,
                    phdr.memsz, phdr.flags, phdr.align = string.unpack(
                        pack.phent, file:read(self.phentsize)
                    )
                end
                self.phdr[i] = phdr
            end
        end

        local strtab, symtab

        if flags & M.PARSE_SECTIONS then
            self.shdr = {}
            if self.shnum > 0 then
                if self.shentsize ~= string.packsize(pack.shent) then
                    log.fatal("invalid section header entry size: " .. self.shentsize .. ", expected " .. string.packsize(pack.shent))
                end
                file:seek("set", self.shoff)
                for i=1,self.shnum do
                    local shdr = {}
                    shdr.name, shdr.type, shdr.flags, shdr.addr, shdr.offset,
                    shdr.size, shdr.link, shdr.info, shdr.addralign, shdr.entsize = string.unpack(
                        pack.shent, file:read(self.shentsize)
                    )
                    self.shdr[i] = shdr
                    if shdr.type == M.SHT_SYMTAB then
                        symtab = shdr
                    end
                end
            end
            if symtab ~= nil then
                strtab = self.shdr[symtab.link + 1]
            end
        end

        local shstrtab = self.shdr[self.shstrndx + 1]

        if flags & M.PARSE_SYMBOLS then
            self.symbols = {}
            local symtab_count = symtab.size / symtab.entsize
            if symtab.entsize ~= string.packsize(pack.sym) then
                log.fatal("invalid symtab entry size: " .. self.shentsize .. ", expected " .. string.packsize(pack.shent))
            end
            file:seek("set", symtab.offset)
            for i=1,symtab_count do
                local sym = {}
                if pack.w == 8 then
                    sym.name, sym.info, sym.other, sym.shndx, sym.value, sym.size = string.unpack(
                        pack.sym, file:read(symtab.entsize)
                    )
                else
                    sym.name, sym.value, sym.size, sym.info, sym.other, sym.shndx = string.unpack(
                        pack.sym, file:read(symtab.entsize)
                    )
                end
                self.symbols[i] = sym
            end
        end

        if flags & M.PARSE_STRTABS then
            if flags & M.PARSE_SECTIONS then
                for i=1,#self.shdr do
                    self.shdr[i].name = M.read_string(file, shstrtab, self.shdr[i].name)
                end
            end
            if flags & M.PARSE_SYMBOLS then
                for i=1,#self.symbols do
                    self.symbols[i].name = M.read_string(file, strtab, self.symbols[i].name)
                end
            end
        end
    end
end

function ELF:get_header_size(file)
    local pack = get_packing(self)
    return 16 + string.packsize(pack.ehdr) + string.packsize(pack.phent) * #self.phdr + string.packsize(pack.shent) * #self.shdr
end

function ELF:write_header(file)
    local pack = get_packing(self)

    self.phoff = 16 + string.packsize(pack.ehdr)
    if #self.phdr == 0 then self.phoff = 0 end
    self.shoff = 16 + string.packsize(pack.ehdr) + string.packsize(pack.phent) * #self.phdr
    if #self.shdr == 0 then self.shoff = 0 end

    file:write(string.pack("<c4BBBBBI7", M.ELF_MAGIC, self.bitness, self.endianness, 1, self.os_abi, self.os_abi_version, 0))
    file:write(string.pack(pack.ehdr,
        self.type,
        self.machine,
        self.version,
        self.entry,
        self.phoff,
        self.shoff,
        self.flags,
        self.ehsize,
        string.packsize(pack.phent), -- phentsize
        #self.phdr,
        string.packsize(pack.shent), -- shentsize
        #self.shdr,
        self.shstrndx))

    for i=1,#self.phdr do
        local phdr = self.phdr[i]
        if w == 8 then
            file:write(string.pack(pack.phent,
                phdr.type, phdr.flags, phdr.offset, phdr.vaddr, phdr.paddr,
                phdr.filesz, phdr.memsz, phdr.align
            ))
        else
            file:write(string.pack(pack.phent,
                phdr.type, phdr.offset, phdr.vaddr, phdr.paddr, phdr.filesz,
                phdr.memsz, phdr.flags, phdr.align 
            ))
        end
    end

    for i=1,#self.shdr do
        local shdr = self.shdr[i]
        file:write(string.pack(pack.shent,
            shdr.name, shdr.type, shdr.flags, shdr.addr, shdr.offset,
            shdr.size, shdr.link, shdr.info, shdr.addralign, shdr.entsize
        ))
    end
end

local StringTable = class()
M.StringTable = StringTable

function StringTable:_init()
    self._strings_ordered = {}
    self.strings = {[""]=0}
    self.len = 1
end

function StringTable:put(s)
    if s == nil then return 0 end
    -- TODO: support substrings
    local pos = self.strings[s]
    if pos == nil then
        pos = self.len
        self.strings[s] = pos
        self.len = self.len + #s + 1
        table.insert(self._strings_ordered, s)
    end
    return pos
end

function StringTable:write(f)
    local zero = string.char(0)
    f:write(zero)
    for i=1,#self._strings_ordered do
        f:write(self._strings_ordered[i], zero)
    end
end

return M
