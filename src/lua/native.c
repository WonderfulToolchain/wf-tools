#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>

static int nativeL_replace(lua_State *L) {
    size_t haystack_length, length;
    const char *haystack = luaL_checklstring(L, 1, &haystack_length);
    char *new_haystack = malloc(haystack_length + 1);
    memcpy(new_haystack, haystack, haystack_length + 1);

    const char *needle = luaL_checklstring(L, 2, &length);
    size_t offset = luaL_checkinteger(L, 3) - 1;
    if (offset + length > haystack_length) {
        length = haystack_length - offset;
    }
    if (length > 0) {
        memcpy(new_haystack + offset, needle, length);
    }
    lua_pushlstring(L, new_haystack, haystack_length);

    return 1;
}

static const luaL_Reg native_funcs[] = {
    { "replace", nativeL_replace },
    { NULL, NULL }
};

int luaopen_wf_internal_native(lua_State* L) {
    luaL_newlib(L, native_funcs);
    
    return 1;
}
