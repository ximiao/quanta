-- cache_mgr.lua
import("kernel/store/mongo_mgr.lua")

local log_err       = logger.err
local log_info      = logger.info
local tunpack       = table.unpack
local tinsert       = table.insert
local check_failed  = utility.check_failed

local KernCode      = enum("KernCode")
local CacheCode     = enum("CacheCode")
local PeriodTime    = enum("PeriodTime")
local SUCCESS       = KernCode.SUCCESS

local event_mgr     = quanta.get("event_mgr")
local timer_mgr     = quanta.get("timer_mgr")
local config_mgr    = quanta.get("config_mgr")

local obj_table     = config_mgr:init_table("cache_obj", "cache_table")
local row_table     = config_mgr:init_table("cache_row", "cache_table")

local CacheMgr = singleton()
local prop = property(CacheMgr)
prop:reader("cache_enable", true)     -- 缓存开关
prop:reader("cache_confs", {})        -- cache_confs
prop:reader("cache_lists", {})        -- cache_lists
prop:reader("dirty_map", nil)         -- dirty objects

function CacheMgr:__init()
    --初始化cache
    self:setup()
    -- 监听rpc事件
    event_mgr:add_listener(self, "rpc_cache_load")
    event_mgr:add_listener(self, "rpc_cache_update")
    event_mgr:add_listener(self, "rpc_cache_update_key")
    event_mgr:add_listener(self, "rpc_cache_delete")
    event_mgr:add_listener(self, "rpc_cache_flush")
    --定时器
    timer_mgr:loop(PeriodTime.SECOND_MS, function(ms)
        self:on_timer_update(ms)
    end)
    timer_mgr:loop(PeriodTime.SECOND_10_MS, function(ms)
        self:on_timer_expire(ms)
    end)
end

function CacheMgr:setup()
    --加载配置
    for _, obj_conf in obj_table:iterator() do
        obj_conf.rows = {}
        local cache_name = obj_conf.cache_name
        self.cache_confs[cache_name] = obj_conf
        self.cache_lists[cache_name] = {}
    end
    for _, row_conf in row_table:iterator() do
        local cache_name = row_conf.cache_name
        local obj_conf =  self.cache_confs[cache_name]
        if obj_conf then
            tinsert(obj_conf.rows, row_conf)
        else
            log_err("[CacheMgr:setup] cache row config obj:%s not exist !", cache_name)
        end
    end
    -- 创建WheelMap
    local WheelMap = import("kernel/basic/wheel_map.lua")
    self.dirty_map = WheelMap(10)
end

function CacheMgr:on_timer_update()
    --存储脏数据
    local now_tick = quanta.now
    for uuid, obj in self.dirty_map:wheel_iterator() do
        if obj:check_store(now_tick) then
            self.dirty_map:set(uuid, nil)
        end
    end
end

function CacheMgr:on_timer_expire()
    --清理超时的记录
    local now_tick = quanta.now
    for cache_name, obj_list in pairs(self.cache_lists) do
        for primary_key, obj in pairs(obj_list) do
            if obj:expired(now_tick) then
                log_info("[CacheMgr][on_timer_expire] cache(%s)'s data(%s) expired!", cache_name, primary_key)
                obj_list[primary_key] = nil
            end
        end
    end
end

--缓存加载
function CacheMgr:load_cache_impl(cache_list, conf, primary_key)
    local CacheObj = import("kernel/cache/cache_obj.lua")
    local cache_obj = CacheObj(conf, primary_key)
    cache_list[primary_key] = cache_obj
    local code = cache_obj:load()
    if check_failed(code) then
        cache_list[primary_key] = nil
        return code
    end
    return SUCCESS, cache_obj
end

function CacheMgr:get_cache_obj(quanta_id, cache_name, primary_key, load_mode)
    local cache_list = self.cache_lists[cache_name]
    if not cache_list then
        log_err("[CacheMgr][get_cache_obj] cache list not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return CacheCode.CACHE_NOT_SUPPERT
    end
    local cache_obj = cache_list[primary_key]
    if cache_obj then
        if cache_obj:is_holding() then
            log_err("[CacheMgr][get_cache_obj] cache is holding! cache_name=%s,primary=%s", cache_name, primary_key)
            return CacheCode.CACHE_IS_HOLDING
        end
        if (not load_mode) and (quanta_id ~= cache_obj:get_lock_node_id()) then
            log_err("[CacheMgr][get_cache_obj] cache node not match! cache_name=%s,primary=%s", cache_name, primary_key)
            return CacheCode.CACHE_KEY_LOCK_FAILD
        end
        cache_obj:active()
        return SUCCESS, cache_obj
    end
    if load_mode then
        local conf = self.cache_confs[cache_name]
        local code, cobj = self:load_cache_impl(cache_list, conf, primary_key)
        if check_failed(code) then
            return code
        end
        cobj:set_lock_node_id(quanta_id)
        return SUCCESS, cobj
    end
    log_err("[CacheMgr][get_cache_obj] cache object not exist! cache_name=%s,primary=%s", cache_name, primary_key)
    return CacheCode.CACHE_IS_NOT_EXIST
end

function CacheMgr:rpc_cache_load(quanta_id, req_data)
    local cache_name, primary_key = tunpack(req_data)
    local code, cache_obj = self:get_cache_obj(quanta_id, cache_name, primary_key, true)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_load] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    cache_obj:set_lock_node_id(quanta_id)
    log_info("[CacheMgr][rpc_cache_load] cache=%s,primary=%s", cache_name, primary_key)
    return SUCCESS, cache_obj:pack()
end

--更新缓存
function CacheMgr:rpc_cache_update(quanta_id, req_data)
    local cache_name, primary_key, table_name, table_data, flush = tunpack(req_data)
    local code, cache_obj = self:get_cache_obj(quanta_id, cache_name, primary_key)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_update] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    local ucode = cache_obj:update(table_name, table_data, flush)
    if cache_obj:is_dirty() then
        self.dirty_map:set(cache_obj:get_uuid(), cache_obj)
    end
    return ucode
end

--更新缓存kv
function CacheMgr:rpc_cache_update_key(quanta_id, req_data)
    local cache_name, primary_key, table_name, table_key, table_value, flush = tunpack(req_data)
    local code, cache_obj = self:get_cache_obj(quanta_id, cache_name, primary_key)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_update_key] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    local ucode = cache_obj:update_key(table_name, table_key, table_value, flush)
    if cache_obj:is_dirty() then
        self.dirty_map:set(cache_obj:get_uuid(), cache_obj)
    end
    return ucode
end

--删除缓存，通常由运维指令执行
function CacheMgr:rpc_cache_delete(quanta_id, req_data)
    local cache_name, primary_key = tunpack(req_data)
    local code, cache_obj = self:get_cache_obj(quanta_id, cache_name, primary_key)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_delete] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    if cache_obj:save() then
        self.cache_lists[cache_name][primary_key] = nil
        self.dirty_map:set(cache_obj:get_uuid(), nil)
        log_info("[CacheMgr][rpc_cache_delete] cache=%s,primary=%s", cache_name, primary_key)
        return SUCCESS
    end
    log_err("[CacheMgr][rpc_cache_delete] save failed: cache=%s,primary=%s", cache_name, primary_key)
    return CacheCode.CACHE_DELETE_SAVE_FAILD
end

--缓存落地
function CacheMgr:rpc_cache_flush(quanta_id, req_data)
    local cache_name, primary_key = tunpack(req_data)
    local code, cache_obj = self:get_cache_obj(quanta_id, cache_name, primary_key)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_flush] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    if cache_obj:save() then
        cache_obj:set_flush(true)
        self.dirty_map:set(cache_obj:get_uuid(), nil)
        log_info("[CacheMgr][rpc_cache_flush] cache=%s,primary=%s", cache_name, primary_key)
        return SUCCESS
    end
    log_err("[CacheMgr][rpc_cache_flush] save failed: cache=%s,primary=%s", cache_name, primary_key)
    return CacheCode.CACHE_DELETE_SAVE_FAILD
end

quanta.cache_mgr = CacheMgr()

return CacheMgr
