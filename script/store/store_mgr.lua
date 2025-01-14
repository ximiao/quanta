--store_mgr.lua

import("store/db_property.lua")
import("agent/cache_agent.lua")

local log_err       = logger.err
local tsort         = table.sort
local tinsert       = table.insert
local qfailed       = quanta.failed
local makechan      = quanta.make_channel

local router_mgr    = quanta.get("router_mgr")
local update_mgr    = quanta.get("update_mgr")
local config_mgr    = quanta.get("config_mgr")
local cache_agent   = quanta.get("cache_agent")

local cache_db      = config_mgr:init_table("cache", "sheet")

local SUCCESS       = quanta.enum("KernCode", "SUCCESS")
local STORE_FLUSH   = environ.number("QUANTA_STORE_FLUSH")

local StoreMgr = singleton()
local prop = property(StoreMgr)
prop:reader("groups", {})       -- groups
prop:reader("stores", {})       -- stores

function StoreMgr:__init()
    cache_db:add_group("group")
    --通知监听
    update_mgr:attach_fast(self)
end

function StoreMgr:find_group(group_name)
    local sgroup = self.groups[group_name]
    if sgroup then
        return sgroup
    end
    sgroup = {}
    for _, sconf in pairs(cache_db:find_group(group_name)) do
        if not sconf.inertable then
            tinsert(sgroup, sconf)
        end
    end
    tsort(sgroup, function(a, b) return a.id < b.id end)
    self.groups[group_name] = sgroup
    return sgroup
end

function StoreMgr:load_impl(primary_id, sheet_name)
    local code, adata = cache_agent:load(primary_id, sheet_name)
    if qfailed(code) then
        log_err("[StoreMgr][load_{}] primary_id: {} find failed! code: {}, res: {}", sheet_name, primary_id, code, adata)
        return false
    end
    local Store = import("store/store.lua")
    local store = Store(sheet_name, primary_id)
    return true, adata, store
end

function StoreMgr:load(entity, primary_id, sheet_name)
    local ok, data, store = self:load_impl(primary_id, sheet_name)
    if not ok then
        return ok
    end
    entity["load_" .. sheet_name .. "_db"](entity, store, data)
    return ok, SUCCESS
end

function StoreMgr:load_group(entity, primary_id, group)
    local channel = makechan("load_group")
    local sheets = self:find_group(group)
    for _, conf in ipairs(sheets) do
        channel:push(function()
            local ok, data, store = self:load_impl(primary_id, conf.sheet)
            if not ok then
                log_err("[StoreMgr][load_{}] primary_id: {} failed! code: {}", conf.sheet, primary_id, data)
                return false, data
            end
            entity["load_" .. conf.sheet .. "_db"](entity, store, data)
            return ok, SUCCESS, data
        end)
    end
    if not channel:execute() then
        return false
    end
    return true, SUCCESS
end

function StoreMgr:delete(object, primary_id, sheet_name)
    self.channel:push(function()
        local code, res = cache_agent:delete(primary_id, sheet_name)
        if qfailed(code) then
            log_err("[StoreMgr][delete] delete ({}) failed primary_id({}), code: {}, res: {}!",  sheet_name, primary_id, code, res)
            object["set_" .. sheet_name .. "_flushing"](object, true)
            return false
        end
        return true, SUCCESS
    end)
end

function StoreMgr:save_store(store, flush)
    if not self.stores[store] then
        self.stores[store] = flush
    end
end

function StoreMgr:on_fast()
    if not router_mgr:available() then
        return
    end
    local channel = makechan("store_mgr")
    for stroe, flush in pairs(self.stores) do
        channel:push(function()
            local sheet_name = stroe:get_sheet()
            local save_data = stroe:load_datas()
            local primary_id = stroe:get_primary_id()
            local code, adata = cache_agent:update(primary_id, sheet_name, save_data, flush)
            if qfailed(code) then
                stroe:merge_datas(save_data)
                self.stores[stroe] = flush
                log_err("[StoreMgr][update_{}] primary_id: {} update failed! code: {}, res: {}", sheet_name, primary_id, code, adata)
                return false
            end
            return true, SUCCESS
        end)
        if channel:isfull(STORE_FLUSH) then
            break
        end
    end
    self.stores = {}
    channel:execute(true)
end

quanta.store_mgr = StoreMgr()

return StoreMgr
