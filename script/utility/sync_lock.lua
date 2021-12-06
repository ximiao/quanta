--sync_lock.lua
--[[提供协程同步锁功能
示例:
    local lock<defer> = thread_mgr:lock(key)
    ...
--]]

local SyncLock  = class()
local prop = property(SyncLock)
prop:reader("thread_mgr", nil)
prop:reader("key", nil)

function SyncLock:__init(thread_mgr, key)
    self.key = key
    self.thread_mgr = thread_mgr
end

function SyncLock:__defer()
    self.thread_mgr:unlock(self.key)
end

return SyncLock
