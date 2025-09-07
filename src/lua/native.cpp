#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#include <cxxabi.h>

static int nativeL_replace(lua_State *L) {
    size_t haystack_length, length;
    const char *haystack = luaL_checklstring(L, 1, &haystack_length);
    char *new_haystack = (char*) malloc(haystack_length + 1);
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
    free(new_haystack);

    return 1;
}

static int nativeL_cxa_demangle(lua_State *L) {
    size_t symbol_length, dest_length;
    int status;
    const char *symbol = luaL_checklstring(L, 1, &symbol_length);
    char *dest = __cxxabiv1::__cxa_demangle(symbol, NULL, &dest_length, &status);

    if (dest == NULL || status < 0 || dest_length == 0) {
        lua_pushlstring(L, symbol, symbol_length);
        if (dest != NULL) {
            free(dest);
        }
    } else {
        lua_pushlstring(L, dest, strlen(dest));
        free(dest);
    }

    return 1;
}

static const luaL_Reg native_funcs[] = {
    { "replace", nativeL_replace },
    { "cxa_demangle", nativeL_cxa_demangle },
    { NULL, NULL }
};

extern "C" {
int luaopen_wf_internal_native(lua_State* L) {
    luaL_newlib(L, native_funcs);

    return 1;
}
}
