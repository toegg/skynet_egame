local skynet = require "skynetex"
require "skynet.manager"
local redis = require "skynet.db.redis"
require "common.etool"

local CMD = {}
local idle_pools = {}
local use_pools = {}
local max_num = 0
local init_num = 0

function CMD.init()
    max_num = tonumber(skynet.getenv("redis_max_num"))
    init_num = tonumber(skynet.getenv("redis_init_num"))

    local rdConf = {
        host = skynet.getenv("redis_host"),
        port = skynet.getenv("redis_port"),
        db = skynet.getenv("redis_db"),
        auth = skynet.getenv("redis_auth")
    }
    --初始化池
    for i = 1, init_num, 1 do
        local rd = redis.connect(rdConf)
        if rd then
            table.insert(idle_pools, rd)
        else
            log_print("redis client init Err:", i) 
        end 
    end
end

function CMD.handle(func, ...)
    local f = function(...)
        local rd = pop_db()
        if rd then
            local handleF = rd[func]
            local res = handleF(rd, ...)
            return rd, res
        else
            return nil, nil
        end
    end
    local rd, res = f(...)
    if rd then
        push_db(rd)
        skynet.ret(skynet.pack({data = res, err = nil}))
    else
        --最多等待5s
        for i = 1, 25, 1 do
            skynet.sleep(20)
            rd, res = f(...)
            if rd then
                push_db(rd)
                skynet.ret(skynet.pack({data = res, err = nil}))
                return
            end
        end
        skynet.ret(skynet.pack({err="not idle redis connect"}))
    end
end

--初始化服务
skynet.start(function(...)
    skynet.name(".rd", skynet.self())
    -- 注册skynet.dispatch处理函数
    skynet.dispatchex("lua", function (session, source, cmd, ...) 
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(f, ...)
        if not status then
            log_print("redis_pool service err:", f, err)
        end
    end)

    --收集info信息
    skynet.info_func(function()
        return idle_pools
    end)
end)

---------------------内部函数
function pop_db()
    --有空闲直接返回
    local rd = idle_pools[1]
    if rd then
        table.remove(idle_pools, 1)
        table.insert(use_pools, rd)
        return rd
    end
    --没达到上限，创建新的连接
    if #use_pools < max_num then
        local rdConf = {
            host = skynet.getenv("redis_host"),
            port = skynet.getenv("redis_port"),
            db = skynet.getenv("redis_db"),
            auth = skynet.getenv("redis_auth")
        } 
        local rd = redis.connect(rdConf)
        if rd then
            table.insert(use_pools, rd)
            return rd
        else
            return nil
        end 
    end

    return nil
end

function push_db(rd)
    if #idle_pools >= init_num then
        rd:disconnect()
        for i = 1, #use_pools, 1 do
            if use_pools[i] == rd then
                table.remove(use_pools, i)
            end
        end
        return
    end
    table.insert(idle_pools, rd)
end