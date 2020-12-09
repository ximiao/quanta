-- cache_obj.lua
-- cache的实体类
local log_err       = logger.err
local check_failed  = utility.check_failed
local check_success = utility.check_success

local KernCode      = enum("KernCode")
local CacheCode     = enum("CacheCode")
local SUCCESS       = KernCode.SUCCESS

local CACHE_CNT_MAX = 100

local mongo_mgr = quanta.mongo_mgr
local CacheRow  = import("kernel/cache/cache_row.lua")

local CacheObj = class()
local prop = property(CacheObj)
prop:accessor("flush", false)           -- flush status
prop:accessor("holding", true)          -- holding status
prop:accessor("lock_node_id", 0)        -- lock node id
prop:accessor("cache_key", "")          -- cache key
prop:accessor("primary_value", nil)     -- primary value
prop:accessor("cache_table", "")        -- cache table
prop:accessor("cache_rows", {})         -- cache rows
prop:accessor("cache_merge", false)     --cache merge mode
prop:accessor("database_id", 0)         -- database id
prop:accessor("update_count", 0)        -- update count
prop:accessor("main_table", "")         -- main table
prop:accessor("active_tick", 0)         -- active tick
prop:accessor("records", {})            -- records
prop:accessor("dirty_records", {})      -- dirty records

function CacheObj:__init(cache_conf, primary_value, database_id)
    self.database_id    = database_id
    self.primary_value  = primary_value
    self.cache_rows     = cache_conf.rows
    self.cache_merge    = cache_conf.cache_merge
    self.cache_key      = cache_conf.cache_key
    self.cache_table    = cache_conf.cache_table
end

function CacheObj:load()
    self.active_tick = quanta.now
    if self.cache_merge then
        --合并加载模式
        local query = { [self.cache_key] = self.primary_value }
        local code, res = mongo_mgr:mongo_find_one(self.database_id, self.cache_table, query, {_id = 0})
        if check_failed(code) then
            log_err("[CacheObj][load] failed: cache_table=%s,res=%s", self.cache_table, res)
            return code
        end
        for _, row_conf in pairs(self.cache_rows) do
            local tab_name = row_conf.cache_table
            local record = CacheRow(row_conf, self.primary_value, self.cache_table, res[tab_name])
            self.records[tab_name] = record
        end
        self.holding = false
        return code
    else
        --分散加载模式
        for _, row_conf in pairs(self.cache_rows) do
            local tab_name = row_conf.cache_table
            local record = CacheRow(row_conf, self.primary_value)
            self.records[tab_name] = record
            local code = record:load(self.database_id)
            if check_failed(code) then
                log_err("[CacheObj][load] load row failed: tab_name=%s", tab_name)
                return code
            end
        end
        self.holding = false
        return SUCCESS
    end
end

function CacheObj:pack()
    local res = {}
    for tab_name, record in pairs(self.records) do
        res[tab_name] = record:get_data()
    end
    return res
end

function CacheObj:is_dirty()
    return next(self.dirty_records)
end

function CacheObj:expired(tick)
    if next(self.dirty_records) then
        return false
    end
    if not self.flush then
        return false
    end
    return self.active_tick < tick
end

function CacheObj:save()
    self.active_tick = quanta.now
    if next(self.dirty_records) then
        self.update_count = 0
        for record in pairs(self.dirty_records) do
            if check_success(record:save()) then
                self.dirty_records[record] = nil
            end
        end
        if next(self.dirty_records) then
            return false
        end
    end
    return true
end

function CacheObj:update(tab_name, tab_data, flush)
    local record = self.records[tab_name]
    if not record then
        return CacheCode.CACHE_KEY_IS_NOT_EXIST
    end
    self.flush = false
    self.active_tick = quanta.now
    self.update_count = self.update_count + 1
    local code =  record:update(tab_data, flush)
    if self.update_count >= CACHE_CNT_MAX then
        self:save()
    end
    if record:is_dirty() then
        self.dirty_records[record] = true
    end
    return code
end

function CacheObj:update_key(tab_name, tab_key, tab_value, flush)
    local record = self.records[tab_name]
    if not record then
        return CacheCode.CACHE_KEY_IS_NOT_EXIST
    end
    self.flush = false
    self.active_tick = quanta.now
    self.update_count = self.update_count + 1
    local code = record:update_key(tab_key, tab_value, flush)
    if self.update_count >= CACHE_CNT_MAX then
        self:save()
    end
    if record:is_dirty() then
        self.dirty_records[record] = true
    end
    return code
end

return CacheObj
