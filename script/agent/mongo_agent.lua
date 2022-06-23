--mongo_agent.lua
local tunpack       = table.unpack
local mrandom       = math_ext.random

local router_mgr    = quanta.get("router_mgr")

local MongoAgent = singleton()
function MongoAgent:__init()
end

--db_query: {coll_name, selector, fields}
function MongoAgent:find_one(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_find_one", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector, fields, sortor, limit}
function MongoAgent:find(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_find", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector, single}
function MongoAgent:delete(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_delete", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, obj, selector, upsert, multi}
function MongoAgent:update(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_update", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, obj}
function MongoAgent:insert(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_insert", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector}
function MongoAgent:count(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_count", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, indexes}
function MongoAgent:create_indexes(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_create_indexes", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, index_name}
function MongoAgent:drop_indexes(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_drop_indexes", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, update, selector, upsert, fields, new}
function MongoAgent:find_and_modify(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_find_and_modify", db_name or "default", tunpack(db_query))
end

--db_query: {cmd, ...}
function MongoAgent:execute(db_query, hash_key, db_name)
    return router_mgr:call_mongo_hash(hash_key or mrandom(), "mongo_execute", db_name or "default", tunpack(db_query))
end

------------------------------------------------------------------
quanta.mongo_agent = MongoAgent()

return MongoAgent
