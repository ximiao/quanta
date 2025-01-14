--thread_mgr.lua
local select        = select
local tsort         = table.sort
local tunpack       = table.unpack
local sformat       = string.format
local co_yield      = coroutine.yield
local co_create     = coroutine.create
local co_resume     = coroutine.resume
local co_running    = coroutine.running
local qxpcall       = quanta.xpcall
local qdefer        = quanta.defer
local synclock      = quanta.synclock
local mrandom       = qmath.random
local tsize         = qtable.size
local log_warn      = logger.warn
local log_err       = logger.err

local QueueFIFO     = import("container/queue_fifo.lua")

local MINUTE_MS     = quanta.enum("PeriodTime", "MINUTE_MS")
local SYNC_PERFRAME = 10

local ThreadMgr = singleton()
local prop = property(ThreadMgr)
prop:reader("session_id", 1)
prop:reader("entry_map", {})
prop:reader("syncqueue_map", {})
prop:reader("coroutine_yields", {})
prop:reader("coroutine_waitings", {})
prop:reader("coroutine_pool", nil)

function ThreadMgr:__init()
    self.session_id = mrandom()
    self.coroutine_pool = QueueFIFO(512)
end

function ThreadMgr:size()
    local co_idle_size = self.coroutine_pool:size()
    local co_yield_size = tsize(self.coroutine_yields)
    local co_wait_size = tsize(self.coroutine_waitings)
    return co_yield_size + co_wait_size + 1, co_idle_size
end

function ThreadMgr:entry(key, func)
    if self.entry_map[key] then
        return false
    end
    self:fork(function()
        local _<close> = qdefer(function()
            self.entry_map[key] = nil
        end)
        self.entry_map[key] = quanta.clock_ms + MINUTE_MS
        func()
    end)
    return true
end

function ThreadMgr:lock(key, waiting)
    local queue = self.syncqueue_map[key]
    if not queue then
        queue = QueueFIFO()
        queue.sync_num = 0
        self.syncqueue_map[key] = queue
    end
    queue.ttl = quanta.clock_ms + MINUTE_MS
    local head = queue:head()
    if not head then
        local lock = synclock(key)
        queue:push(lock)
        return lock
    end
    if head.co == co_running() then
        --防止重入
        head:lock()
        return head
    end
    if waiting then
        --等待则挂起
        local lock = synclock(key)
        queue:push(lock)
        co_yield()
        return lock
    end
end

function ThreadMgr:unlock(key, force)
    local queue = self.syncqueue_map[key]
    if not queue then
        return
    end
    local head = queue:head()
    if not head then
        return
    end
    if head.co == co_running() or force then
        queue:pop()
        local next = queue:head()
        if next then
            local sync_num = queue.sync_num
            if sync_num < SYNC_PERFRAME then
                queue.sync_num = sync_num + 1
                co_resume(next.co)
                return
            end
            self.coroutine_waitings[next.co] = 0
        end
        queue.sync_num = 0
    end
end

function ThreadMgr:create_co(f)
    local pool = self.coroutine_pool
    local co = pool:pop()
    if co == nil then
        co = co_create(function(...)
            qxpcall(f, "[ThreadMgr][co_create] fork error: {}", ...)
            while true do
                f = nil
                pool:push(co)
                f = co_yield()
                if type(f) == "function" then
                    qxpcall(f, "[ThreadMgr][co_create] fork error: {}", co_yield())
                end
            end
        end)
    else
        co_resume(co, f)
    end
    return co
end

function ThreadMgr:try_response(session_id, ...)
    local context = self.coroutine_yields[session_id]
    if context then
        self.coroutine_yields[session_id] = nil
        self:resume(context.co, ...)
        return true
    end
    return false
end

function ThreadMgr:response(session_id, ...)
    local context = self.coroutine_yields[session_id]
    if not context then
        log_warn("[ThreadMgr][response] unknown session_id({}) response!", session_id)
        return
    end
    self.coroutine_yields[session_id] = nil
    self:resume(context.co, ...)
end

function ThreadMgr:resume(co, ...)
    return co_resume(co, ...)
end

function ThreadMgr:yield(session_id, title, ms_to, ...)
    local context = {co = co_running(), title = title, to = quanta.clock_ms + ms_to}
    self.coroutine_yields[session_id] = context
    return co_yield(...)
end

function ThreadMgr:on_second30(clock_ms)
    for key, queue in pairs(self.syncqueue_map) do
        if queue:empty() and clock_ms > queue.ttl then
            self.syncqueue_map[key] = nil
        end
    end
    for key, clock_to in pairs(self.entry_map) do
        if clock_ms > clock_to then
            self.entry_map[key] = nil
        end
    end
end

function ThreadMgr:on_fast(clock_ms)
    --检查协程超时
    local timeout_coroutines = {}
    for co, ms_to in pairs(self.coroutine_waitings) do
        if ms_to <= clock_ms then
            timeout_coroutines[#timeout_coroutines + 1] = co
        end
    end
    --处理协程超时
    if next(timeout_coroutines) then
        for _, co in pairs(timeout_coroutines) do
            self.coroutine_waitings[co] = nil
            co_resume(co)
        end
    end
end

function ThreadMgr:on_second(clock_ms)
    --处理锁超时
    for key, queue in pairs(self.syncqueue_map) do
        local head = queue:head()
        if head and head:is_timeout(clock_ms) then
            self:unlock(key, true)
        end
    end
    --检查协程超时
    local timeout_coroutines = {}
    for session_id, context in pairs(self.coroutine_yields) do
        if context.to <= clock_ms then
            context.session_id = session_id
            timeout_coroutines[#timeout_coroutines + 1] = context
        end
    end
    --处理协程超时
    if next(timeout_coroutines) then
        tsort(timeout_coroutines, function(a, b) return a.to < b.to end)
        for _, context in ipairs(timeout_coroutines) do
            local session_id = context.session_id
            self.coroutine_yields[session_id] = nil
            if context.title then
                log_err("[ThreadMgr][on_second] session_id({}:{}) timeout!", session_id, context.title)
            end
            self:resume(context.co, false, sformat("%s timeout", context.title), session_id)
        end
    end
end

function ThreadMgr:fork(f, ...)
    local n = select("#", ...)
    local co
    if n == 0 then
        co = self:create_co(f)
    else
        local args = { ... }
        co = self:create_co(function() f(tunpack(args, 1, n)) end)
    end
    self:resume(co, ...)
    return co
end

function ThreadMgr:sleep(ms)
    local co = co_running()
    self.coroutine_waitings[co] = quanta.clock_ms + ms
    co_yield()
end

function ThreadMgr:build_session_id()
    self.session_id = self.session_id + 1
    if self.session_id >= 0x7fffffff then
        self.session_id = 1
    end
    return self.session_id
end

function ThreadMgr:success_call(period, success_func, interval, try_time)
    self:fork(function()
        if interval then
            self:sleep(interval)
        end
        try_time = try_time or 10
        while true do
            if success_func() or try_time <= 0 then
                break
            end
            try_time = try_time - 1
            self:sleep(period)
        end
    end)
end

quanta.thread_mgr = ThreadMgr()

return ThreadMgr
