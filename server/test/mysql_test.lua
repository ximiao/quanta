-- mysql_test.lua
local log_debug = logger.debug

local timer_mgr = quanta.get("timer_mgr")

local MysqlMgr  = import("store/mysql_mgr.lua")
local mysql_mgr = MysqlMgr()

local MAIN_DBID = environ.number("QUANTA_MYSQL_MAIN_ID")

timer_mgr:once(3000, function()
    local code, res_oe = mysql_mgr:execute(MAIN_DBID, "drop table test_mysql")
    log_debug("db drop table code: %s, err = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "create table if not exists test_mysql (id int auto_increment, pid int, value int, primary key (id))")
    log_debug("db create table code: %s, err = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "select count(*) as count from test_mysql where pid=123456")
    log_debug("db select code: %s, count = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "insert into test_mysql (pid, value) values (123457, 40)")
    log_debug("db insert code: %s, count = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "select * from test_mysql where pid = 123456")
    log_debug("db select code: %s, res_oe = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "update test_mysql set pid = 123454, value = 20 where pid = 123456 limit 1")
    log_debug("db update code: %s, err = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "select * from test_mysql")
    log_debug("db select code: %s, res_oe = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "delete from test_mysql where pid = 123457")
    log_debug("db delete code: %s, err = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "replace into test_mysql (id, pid, value) values (1, 123457, 40)")
    log_debug("db replace code: %s, count = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "select * from test_mysql")
    log_debug("db select code: %s, res_oe = %s", code, res_oe)
    code, res_oe = mysql_mgr:execute(MAIN_DBID, "select count(*) as count from test_mysql where pid=123456")
    log_debug("db count code: %s, count = %s", code, res_oe)
end)