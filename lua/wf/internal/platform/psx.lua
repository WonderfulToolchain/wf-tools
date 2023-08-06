-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Helpers for the "psx" target.
-- @module wf.internal.platform.psx
-- @alias M

local wfmath = require("wf.internal.math")
local M = {}

function M.create_exe_header(header)
    return string.pack("<c8I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4c1972",
        "PS-X EXE",
        0, 0,
        header.pc,
        header.gp or 0,
        header.load_address,
        header.load_length,
        0, 0,
        header.bss_address or 0,
        header.bss_length or 0,
        header.sp_base or 0x801FFFF0,
        header.sp_offset or 0,
        0, 0, 0, 0, 0,
        header.marker or ""
    )
end

return M
