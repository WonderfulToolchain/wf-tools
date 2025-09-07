-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

--- Terminal library.

local compat = require("pl.compat")
local is_tty = true
if not compat.is_windows then
    local posix_stdio = require("posix.stdio")
    local posix_unistd = require("posix.unistd")
    is_tty = posix_unistd.isatty(posix_stdio.fileno(io.stdin))
end

local M = {}

M.use_color = (#(os.getenv("NO_COLOR") or "") <= 0) and is_tty

local ansi_prefix = string.char(27) .. "["
local function wrap_ansi_code(code)
    code = ansi_prefix .. code
    return function(s)
        if s ~= nil then
            if M.use_color then return code .. s .. ansi_prefix .. "0m" else return s end
        else
            if M.use_color then return code else return "" end
        end
    end
end

M.reset = wrap_ansi_code("0m")
M.bold = wrap_ansi_code("1m")
M.underline = wrap_ansi_code("4m")
M.inverse = wrap_ansi_code("7m")

M.fg = {}
M.fg.black = wrap_ansi_code("30m")
M.fg.red = wrap_ansi_code("31m")
M.fg.green = wrap_ansi_code("32m")
M.fg.yellow = wrap_ansi_code("33m")
M.fg.blue = wrap_ansi_code("34m")
M.fg.purple = wrap_ansi_code("35m")
M.fg.cyan = wrap_ansi_code("36m")
M.fg.white = wrap_ansi_code("37m")
M.fg.bright_black = wrap_ansi_code("90m")
M.fg.bright_red = wrap_ansi_code("91m")
M.fg.bright_green = wrap_ansi_code("92m")
M.fg.bright_yellow = wrap_ansi_code("93m")
M.fg.bright_blue = wrap_ansi_code("94m")
M.fg.bright_purple = wrap_ansi_code("95m")
M.fg.bright_cyan = wrap_ansi_code("96m")
M.fg.bright_white = wrap_ansi_code("97m")

M.bg = {}
M.bg.black = wrap_ansi_code("40m")
M.bg.red = wrap_ansi_code("41m")
M.bg.green = wrap_ansi_code("42m")
M.bg.yellow = wrap_ansi_code("43m")
M.bg.blue = wrap_ansi_code("44m")
M.bg.purple = wrap_ansi_code("45m")
M.bg.cyan = wrap_ansi_code("46m")
M.bg.white = wrap_ansi_code("47m")
M.bg.bright_black = wrap_ansi_code("100m")
M.bg.bright_red = wrap_ansi_code("101m")
M.bg.bright_green = wrap_ansi_code("102m")
M.bg.bright_yellow = wrap_ansi_code("103m")
M.bg.bright_blue = wrap_ansi_code("104m")
M.bg.bright_purple = wrap_ansi_code("105m")
M.bg.bright_cyan = wrap_ansi_code("106m")
M.bg.bright_white = wrap_ansi_code("107m")

M.strip = function(s)
    return string.gsub(s, "\x1b%[%d+%l", "")
end

return M
