-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- .c/.h file generator.
-- @module wf.internal.bin2c
-- @alias M

local M = {}

function M.bin2c(c_file, h_file, program_name, entries)
    local current_date = os.date()
    local comment_header = "// autogenerated by " .. program_name .. " on " .. current_date .. "\n\n"
    local c_values_per_line <const> = 12

    if h_file ~= nil then
        h_file:write(comment_header)
        h_file:write("#pragma once\n#include <stddef.h>\n#include <stdint.h>\n#include <wonderful.h>\n\n")
    end

    if c_file ~= nil then
        c_file:write(comment_header)
        c_file:write("#include <stddef.h>\n#include <stdint.h>\n#include <wonderful.h>\n\n")
    end

    for array_name, entry in pairs(entries) do
        local data = entry.data
        local dtype = entry.type or "uint8_t"
        local endian = entry.endian or "little"
        local width
        if dtype == "uint8_t" or dtype == "int8_t" then
            width = 1
        elseif dtype == "uint16_t" or dtype == "int16_t" then
            width = 2
        elseif dtype == "uint32_t" or dtype == "int32_t" then
            width = 4
        else
            error("unsupported datatype: " .. dtype)
        end
        if endian ~= "little" and endian ~= "big" then
            error("unsupported endianness: " .. endian)
        end

        local attributes = entry.attributes or {}
        if entry.align then
            table.insert(attributes, "aligned(" .. entry.align .. ")")
        end
        if entry.section then
            table.insert(attributes, "section(\"" .. entry.section .. "\")")
        end

        if h_file ~= nil then
            h_file:write("#define " .. array_name .. "_size (" .. #data .. ")\n")
            h_file:write("extern const " .. dtype .. " ")
            if entry.address_space then
                h_file:write(entry.address_space .. " ")
            end
            h_file:write(array_name .. "[" .. #data .. "];\n")
            if entry.bank then
                h_file:write("extern const void *__bank_" .. array_name .. ";\n")
                h_file:write("#define " .. array_name .. "_bank ((size_t) &__bank_" .. array_name .. ")\n")
            end
        end

        local write_data_number = nil
        if type(data) == "string" then
            if width == 1 then
                write_data_number = function(i) c_file:write(string.format("0x%02X", data:byte(i))) end
            elseif width == 2 then
                if endian == "big" then
                    write_data_number = function(i) c_file:write(string.format("0x%02X%02X", data:byte(i), data:byte(i + 1) or 0)) end
                else
                    write_data_number = function(i) c_file:write(string.format("0x%02X%02X", data:byte(i + 1) or 0, data:byte(i))) end
                end
            elseif width == 4 then
                if endian == "big" then
                    write_data_number = function(i) c_file:write(string.format("0x%02X%02X%02X%02X", data:byte(i), data:byte(i + 1) or 0, data:byte(i + 2) or 0, data:byte(i + 3) or 0)) end
                else
                    write_data_number = function(i) c_file:write(string.format("0x%02X%02X%02X%02X", data:byte(i + 3) or 0, data:byte(i + 2) or 0, data:byte(i + 1) or 0, data:byte(i))) end
                end
            end
        else
            write_data_number = function(i) c_file:write(string.format("%d", data[i])) end
        end
    
        if c_file ~= nil then
            c_file:write("const " .. dtype .. " ")
            if entry.address_space then
                c_file:write(entry.address_space .. " ")
            end
            c_file:write(array_name .. "[" .. #data .. "] ")
            if #attributes > 0 then
                c_file:write("__attribute__((")
                for i=1,#attributes do
                    if i > 1 then c_file:write(", ") end
                    c_file:write(attributes[i])
                end
                c_file:write(")) ")
            end
            c_file:write("= {");
            for i = 1, #data, width do
                if i > 1 then
                    c_file:write(",")
                end
                if (i % c_values_per_line) == 1 then
                    c_file:write("\n\t")
                else
                    c_file:write(" ")
                end
                write_data_number(i)
            end
            c_file:write("\n};\n");
        end
    end
end

return M
