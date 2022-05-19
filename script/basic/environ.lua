--environ.lua
local pairs     = pairs
local tonumber  = tonumber
local ogetenv   = os.getenv
local log_info  = logger.info
local tunpack   = table.unpack
local saddr     = string_ext.addr
local ssplit    = string_ext.split
local protoaddr = string_ext.protoaddr

environ = {}

--环境变量表
local QUANTA_ENV = _ENV.QUANTA_ENV or {}

function environ.init()
    if quanta.platform == "windows" then
        QUANTA_ENV.QUANTA_DAEMON = 0
        QUANTA_ENV.QUANTA_STATIS = 1
        QUANTA_ENV.QUANTA_PERFEVAL = 1
    end
    log_info("---------------------environ value dump-------------------")
    for name, value in pairs(QUANTA_ENV) do
        log_info("%s ----> %s", name, value)
    end
    log_info("----------------------------------------------------------")
    return environ.number("QUANTA_MODE", 4)
end

function environ.get(key, def)
    return QUANTA_ENV[key] or ogetenv(key) or def
end

function environ.number(key, def)
    return tonumber(QUANTA_ENV[key] or ogetenv(key) or def)
end

function environ.status(key)
    return (tonumber(QUANTA_ENV[key] or ogetenv(key) or 0) > 0)
end

function environ.addr(key)
    local value = QUANTA_ENV[key] or ogetenv(key)
    if value then
        return saddr(value)
    end
end

function environ.protoaddr(key)
    local value = QUANTA_ENV[key] or ogetenv(key)
    if value then
        return protoaddr(value)
    end
end

function environ.split(key, val)
    local value = QUANTA_ENV[key] or ogetenv(key)
    if value then
        return tunpack(ssplit(value, val))
    end
end

function environ.table(key, str)
    return ssplit(QUANTA_ENV[key] or ogetenv(key) or "", str or ",")
end
