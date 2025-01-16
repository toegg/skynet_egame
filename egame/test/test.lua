local skynet = require "skynet"
local mysql = require "skynet.db.mysql"
require "common.etool"

local CMD = {}
local idle_pools = {}
local use_pools = {}
local max_num = 0
local init_num = 0

function CMD.init()
    max_num = tonumber(skynet.getenv("db_max_num"))
    init_num = tonumber(skynet.getenv("db_init_num"))

    local connect_info = {host=skynet.getenv("host"), port=skynet.getenv("port"), 
        database=skynet.getenv("database"), user=skynet.getenv("user"), password=skynet.getenv("pwd")}
    local db1 = mysql.connect(connect_info)
    local d = db1:query(string.format("select * from player where role_id=%d", 0))
    log_print(#d, d== nil)
    print("------------")
    print_table(db1:query(string.format("select * from player where id=%d", 0)))
    --初始化池
    for i = 1, init_num, 1 do
        local db = mysql.connect(connect_info)
        if db then
            table.insert(idle_pools, db)
        else
            log_print("db init Err:", i) 
        end 
    end
end

function CMD.handle(sql)
    local f = function()
        local db = pop_db()
        if db then
            local res = db.query(sql)
            return db, res
        else
            return nil, nil
        end
    end
    local db, res = f()
    if res then
        push_db(db)
        skynet.ret(skynet.pack(res))
    else
        for i = 1, 3, 1 do
            skynet.sleep(20)
            db, res = f()
            if res then
                push_db(db)
                skynet.ret(skynet.pack(res))
                return
            end
        end
        skynet.ret(skynet.pack({err="not idle db connect"}))
    end
end

--初始化服务
skynet.start(function(...)
    -- 注册skynet.dispatch处理函数
    skynet.dispatch("lua", function (session, source, cmd, ...) 
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(f, ...)
        if not status then
            log_print("db service err:", err)
        end
    end)
end)

---------------------内部函数
function pop_db()
    --有空闲直接返回
    local db = idle_pools[1]
    if db then
        table.remove(idle_pools, 1)
        table.insert(use_pools, db)
        return db
    end
    --没达到上限，创建新的连接
    if #use_pools < max_num then
        local connect_info = {host=skynet.getenv("host"), port=skynet.getenv("port"), 
            database=skynet.getenv("database"), user=skynet.getenv("user"), password=skynet.getenv("pwd")} 
        local db = mysql.connect(connect_info)  
        if db then
            table.insert(use_pools, db)
            return db
        else
            return nil
        end 
    end

    return nil
end

function push_db(db)
    if #idle_pools >= init_num then
        db.disconnect()
        for i = 1, #use_pools, 1 do
            if use_pools[i] == db then
                table.remove(use_pools, i)
            end
        end
        return
    end
    table.insert(idle_pools, db)
end