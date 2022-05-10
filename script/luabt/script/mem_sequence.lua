--mem_sequence.lua
local ipairs        = ipairs
local FAIL          = luabt.FAIL
local SUCCESS       = luabt.SUCCESS
local RUNNING       = luabt.RUNNING
local node_execute  = luabt.node_execute

local MSequenceNode = class()
function MSequenceNode:__init(...)
    self.name = "mem_sequence"
    self.children = {...}
end

function MSequenceNode:open(_, node_data)
    node_data.runningChild = 1
end

function MSequenceNode:run(btree, node_data)
    local child = node_data.runningChild
    for i = child, #self.children do
        local status = node_execute(self.children[i], btree, node_data.__level + 1)
        if status == FAIL then
            return status
        end
        if status == RUNNING then
            node_data.runningChild = i
            return status
        end
    end
    return SUCCESS
end

function MSequenceNode:close(btree, node_data)
    node_data.runningChild = 1
    for _, node in ipairs(self.children) do
        local child_data = btree[node]
        if child_data and child_data.is_open then
            child_data.is_open = false
            if node.close then
                node:close(btree, child_data)
            end
        end
    end
end

return MSequenceNode
