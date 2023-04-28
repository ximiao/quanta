--game_dao.lua
import("store/db_property.lua")
import("agent/mongo_agent.lua")
import("agent/cache_agent.lua")

local log_err       = logger.err
local log_debug     = logger.debug
local tunpack       = table.unpack
local tinsert       = table.insert
local qfailed       = quanta.failed

local event_mgr     = quanta.get("event_mgr")
local mongo_agent   = quanta.get("mongo_agent")
local cache_agent   = quanta.get("cache_agent")

local USE_CACHE     = environ.status("QUANTA_DB_USE_CACHE")

local GameDAO = singleton()
local prop = property(GameDAO)
prop:reader("sheet_groups", {})
prop:reader("sheet_indexs", {})

function GameDAO:__init()
    event_mgr:add_listener(self, "on_db_prop_update")
    event_mgr:add_listener(self, "on_db_prop_remove")
end

function GameDAO:add_sheet(group, sheet_name, primary_key, inertia)
    if not self.sheet_indexs[sheet_name] then
        self.sheet_indexs[sheet_name] = { primary_key, group, { [sheet_name] = 1 } }
        if not inertia then
            local sheets = self.sheet_groups[group]
            if not sheets then
                self.sheet_groups[group] = { sheet_name }
            else
                tinsert(sheets, sheet_name)
            end
        end
    end
end

function GameDAO:load_impl(primary_id, sheet_name)
    local primary_key, group, filters = self:find_primary_key(sheet_name)
    if not primary_key then
        return false
    end
    if USE_CACHE then
        local code, adata = cache_agent:load(primary_id, sheet_name, primary_key, filters, group)
        if qfailed(code) then
            log_err("[GameDAO][load_%s] primary_id: %s find failed! code: %s, res: %s", sheet_name, primary_id, code, adata)
            return false
        end
        return true, adata
    end
    return self:load_mongo(sheet_name, primary_id, primary_key, filters)
end

function GameDAO:load_mongo(sheet_name, primary_id, primary_key, filters)
    local ok, code, adata = mongo_agent:find_one({ sheet_name, { [primary_key] = primary_id }, filters })
    if qfailed(code, ok) then
        log_err("[GameDAO][load_mongo_%s] primary_id: %s find failed! code: %s, res: %s", sheet_name, primary_id, code, adata)
        return false
    end
    return true, adata or {}
end

function GameDAO:load(entity, primary_id, sheet_name)
    local function load_sheet_db()
        return self:load_impl(primary_id, sheet_name)
    end
    local ok = entity["load_" .. sheet_name .. "_db"](entity, primary_id, load_sheet_db)
    if not ok then
        log_err("[GameDAO][load] load %s failed! primary_id: %s", sheet_name, primary_id)
        return false
    end
    return true
end

function GameDAO:load_group(entity, group, primary_id)
    for _, sheet_name in ipairs(self.sheet_groups[group] or {}) do
        if not self:load(entity, primary_id, sheet_name) then
            return false
        end
    end
    return true
end

function GameDAO:update_field(primary_id, sheet_name, field, field_data, flush)
    local primary_key = self:find_primary_key(sheet_name)
    if not primary_key then
        return false
    end
    if USE_CACHE then
        local code, adata = cache_agent:update_field(primary_id, sheet_name, field, field_data, flush)
        if qfailed(code) then
            log_err("[GameDAO][update_field_%s] primary_id: %s find failed! code: %s, res: %s", sheet_name, primary_id, code, adata)
            return false
        end
        return true
    end
    return self:update_mongo_field(sheet_name, primary_id, primary_key, field, field_data)
end

function GameDAO:update_mongo_field(sheet_name, primary_id, primary_key, field, field_data)
    local udata = { ["$set"] = { [field] = field_data } }
    local ok, code, res = mongo_agent:update({ sheet_name, udata, { [primary_key] = primary_id }, true })
    if qfailed(code, ok) then
        log_err("[GameDAO][update_mongo_field_%s] update (%s) failed! primary_id(%s), code(%s), res(%s)", sheet_name, field, primary_id, code, res)
        return false
    end
    return true
end

function GameDAO:remove_field(primary_id, sheet_name, field, flush)
    local primary_key = self:find_primary_key(sheet_name)
    if not primary_key then
        return false
    end
    if USE_CACHE then
        local code, res = cache_agent:remove_field(primary_id, sheet_name, field, flush)
        if qfailed(code) then
            log_err("[GameDAO][remove_field_%s] remove (%s) failed primary_id(%s), code: %s, res: %s!", sheet_name, field, primary_id, code, res)
            return false
        end
        return true
    end
    return self:remove_mongo_field(sheet_name, primary_id, primary_key, field)
end

function GameDAO:remove_mongo_field(sheet_name, primary_id, primary_key, field)
    local udata = { ["$unset"] = { [field] = 1 } }
    local ok, code, res = mongo_agent:update({ sheet_name, udata, { [primary_key] = primary_id }, true })
    if qfailed(code, ok) then
        log_err("[GameDAO][remove_field_%s] remove (%s) failed primary_id(%s), code: %s, res: %s!", sheet_name, field, primary_id, code, res)
        return false
    end
    return true
end

function GameDAO:delete(primary_id, sheet_name)
    local primary_key = self:find_primary_key(sheet_name)
    if not primary_key then
        return false
    end
    if USE_CACHE then
        local code, res = cache_agent:delete(primary_id, sheet_name)
        if qfailed(code) then
            log_err("[GameDAO][delete] delete (%s) failed primary_id(%s), code: %s, res: %s!",  sheet_name, primary_id, code, res)
            return false
        end
        return true
    end
    return self:delete_mongo(sheet_name, primary_id, primary_key)
end

function GameDAO:delete_mongo(sheet_name, primary_id, primary_key)
    local ok, code, res = mongo_agent:delete({ sheet_name, { [primary_key] = primary_id }, true })
    if qfailed(code, ok) then
        log_err("[GameDAO][delete_mongo_%s] delete failed primary_id(%s), code: %s, res: %s!", sheet_name, primary_id, code, res)
        return false
    end
    return true
end

function GameDAO:flush(primary_id, group)
    if USE_CACHE then
        local code, res = cache_agent:flush(primary_id, group)
        if qfailed(code) then
            log_err("[GameDAO][flush] flush (%s) failed primary_id(%s), code: %s, res: %s!",  primary_id, code, res)
            return false
        end
    end
    return true
end

function GameDAO:find_primary_key(sheet_name)
    local sheet = self.sheet_indexs[sheet_name]
    if not sheet then
        log_err("[GameDAO][find_primary_key] sheet %s not defined primary_key!", sheet_name)
        return false
    end
    return tunpack(sheet)
end

function GameDAO:on_db_prop_update(primary_id, sheet_name, db_key, value, flush)
    log_debug("[GameDAO][on_db_prop_update] primary_id: %s sheet_name: %s, db_key: %s", primary_id, sheet_name, db_key)
    return self:update_field(primary_id, sheet_name, db_key, value, flush)
end

function GameDAO:on_db_prop_remove(primary_id, sheet_name, db_key, flush)
    log_debug("[GameDAO][on_db_prop_remove] primary_id: %s sheet_name: %s, db_key: %s", primary_id, sheet_name, db_key)
    return self:remove_field(primary_id, sheet_name, db_key, flush)
end

quanta.game_dao = GameDAO()

return GameDAO