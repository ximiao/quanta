#define LUA_LIB

#include "scheduler.h"

namespace lworker {

    static scheduler schedulor;
    luakit::lua_table open_lworker(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto llworker = kit_state.new_table();
        llworker.set_function("shutdown", []() { schedulor.shutdown(); });
        llworker.set_function("update", [&](uint64_t clock_ms) { schedulor.update(clock_ms); });
        llworker.set_function("broadcast", [&](lua_State* L) { return schedulor.broadcast(L); });
        llworker.set_function("setup", [](lua_State* L, std::string_view service, std::string_view sandbox) {
            schedulor.setup(L, service, sandbox);
            return 0;
        });
        llworker.set_function("startup", [](std::string_view name, std::string_view entry) {
            return schedulor.startup(name, entry);
        });
        llworker.set_function("call", [](lua_State* L, std::string_view name) {
            return schedulor.call(L, name);
        });
        return llworker;
    }
}

extern "C" {
    LUALIB_API int luaopen_lworker(lua_State* L) {
        auto llworker = lworker::open_lworker(L);
        return llworker.push_stack();
    }
}
