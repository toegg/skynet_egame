local skynet = require "skynetex"
local queue = require "skynet.queue"
require "skynet.manager"
local cjson = require "cjson"
require "cache.cache_config"
require "def.def_cache"
require "common.etool"
local db = require "db.db_api"


local q = queue()
local CMD = {}

local state = BASE_CACHE_MGR
local gc_time = 20 * 60 -- gc缓存和redis数据的间隔

----------------内部函数

--gc缓存和redis数据
local function gc_data()
    skynet.timeout(gc_time * 100, gc_data)
    for k, v in pairs(state.caches) do
        --每个进程休眠2s，避免一直操作redis
        skynet.send(v.fd, "lua", "gc_data")
        skynet.sleep(200)
    end
end

---初始化
local function InitCache()
    --初始化数据
    state.caches = {}
    state.wait_map = {}
    state.write_map = {}
    state.wait_del_map = {}
    state.wait_truncate_map = {}
    state.del_map = {}
    state.save_timer = nil
    skynet.name(".cache_mgr", skynet.self())
    --开启服务进程
    for k, v in pairs(CACHE_LIST) do
        local fd = skynet.newservice("cache", k, v)
        local cache = BASE_CACHE
        cache.type = k
        cache.conf = v
        cache.fd = fd
        state.caches[k] = cache
    end
    skynet.timeout(gc_time * 100, gc_data)
end

---写入
local function db_write(tab, datas)
    local num = 0
    for k, v in pairs(datas) do
        --50个则休息一下500ms
        if num >= 50 then
            skynet.sleep(50)
        end

        num = num + 1
        local conf = v.conf
        local data = v.data
        local config = skynet.load(conf)
        if config then
            local tabInfo = config.table(tab)
            if tabInfo then
                local fields = tabInfo["field"]
                local jsonFields = tabInfo["json"] or {}
                local fieldStr = ""
                local valStr = ""
                for k, v in pairs(fields) do
                    if not data[v] then
                        return false
                    end
                    if is_in_table(jsonFields, v) then
                        data[v] = "'"..cjson.encode(data[v]).."'"
                    end
                    if fieldStr == "" then
                        fieldStr = fieldStr..v
                        valStr = valStr..data[v]
                    else
                        fieldStr = fieldStr..","..v
                        valStr = valStr..","..data[v]
                    end
                end
                local sql = string.format("replace into %s (%s) values (%s)", tab, fieldStr, valStr)
                local result = db.query(sql)
                if result.err == nil then
                    skynet.send(skynet.localname("."..conf), "lua", "finish_db_save", tab, k)
                else
                    log_print("db Err:", result.err)
                end
            end
        end
    end
    state.write_map[tab] = nil
    log_print("finish db save", tab)
    if not state.write_map or table_len(state.write_map) == 0 then
        db_del_handle()
    end
end

---移除
local function db_del(tab, datas)
    local num = 0
    local dels = datas["index"] or {}
    for k, v in pairs(dels) do
        k = cjson.decode(k)
        --50个则休息一下500ms
        if num >= 50 then
            skynet.sleep(50)
        end

        num = num + 1
        local conf = v.conf
        local config = skynet.load(conf)
        if config then
            local tabInfo = config.table(tab)
            if tabInfo then
                local indexs = tabInfo["index"]
                local valStr = ""
                for kk, vv in pairs(indexs) do
                    if not k[kk] then
                        return false
                    end
                    if valStr == "" then
                        valStr = valStr..vv.."="..k[kk]
                    else
                        valStr = valStr.." and "..vv.."="..k[kk]
                    end
                end
                local sql = string.format("delete from %s where %s", tab, valStr)
                local result = db.query(sql)
                if result.err == nil then
                    skynet.send(skynet.localname("."..conf), "lua", "finish_db_del", tab, k, 1, {key = v.key})
                else
                    log_print("db Err:", result.err)
                end
            end
        end
    end
    dels = datas["all"] or {}
    for k, v in pairs(dels) do
        --50个则休息一下500ms
        if num >= 50 then
            skynet.sleep(50)
        end

        num = num + 1
        local conf = v.conf
        local config = skynet.load(conf)
        if config then
            local tabInfo = config.table(tab)
            if tabInfo then
                local index = tabInfo["main_index"]
                local sql = string.format("delete from %s where %s=%s", tab, index, k)
                local result = db.query(sql)
                if result.err == nil then
                    skynet.send(skynet.localname("."..conf), "lua", "finish_db_del", tab, k, 2, {key = v.key, indexs= v.indexs})
                else
                    log_print("db Err:", result.err)
                end
            end
        end
    end
    state.del_map[tab] = nil
    log_print("finish db del", tab)   
    if not state.del_map or table_len(state.del_map) == 0 then
        db_truncate_handle()
    end
end

---清表
local function db_truncate(tab, v)
    local conf = v.conf
    local config = skynet.load(conf)
    if config then
        local tabInfo = config.table(tab)
        if tabInfo then
            local sql = nil
            if v.type == 1 then
                sql = string.format("delete from %s", tab)
            else
                sql = string.format("truncate %s", tab)
            end
            local result = db.query(sql)
            if result.err == nil then
                skynet.send(skynet.localname("."..conf), "lua", "finish_db_truncate", tab)
            else
                log_print("db Err:", result.err)
            end
        end
    end
    state.del_map[tab] = nil
    log_print("finish db truncate", tab) 
end

--执行写入操作
local function db_save_handle()
    state.save_timer = nil
    local forkNum  = 0
    for k, v in pairs(state.wait_map) do
        if table_len(v) > 0 then
            if not state.write_map[k] then
                skynet.fork(db_write, k, v)
                forkNum = forkNum + 1
                state.write_map[k] = v
                state.wait_map[k] = nil
            else            
                --同表正在写入中，则下次再写
                start_timer()
            end 
        end
    end
    if forkNum == 0 then
        db_del_handle()
    end
end

--执行删除操作
function db_del_handle()
    local forkNum  = 0
    for k, v in pairs(state.wait_del_map) do
        if table_len(v) > 0 then
            if not state.del_map[k] then
                skynet.fork(db_del, k, v)
                forkNum = forkNum + 1
                state.del_map[k] = v
                state.wait_del_map[k] = nil
            else
                --同表正在删除中，则下次再删
                skynet.send(skynet.localname(".cache_mgr"), "lua", "start_timer")
            end
        end
    end
    if forkNum == 0 then
        db_truncate_handle()
    end
end

--执行清表操作
function db_truncate_handle()
    for k, v in pairs(state.wait_truncate_map) do
        if not state.del_map[k] then
            skynet.fork(db_truncate, k, v)
            state.del_map[k] = v
            state.wait_truncate_map[k] = nil
        else
            --同表正在删除中，则下次再删
            skynet.send(skynet.localname(".cache_mgr"), "lua", "start_timer")
        end
    end
end

---开启写入定时器
function start_timer()
    if state.save_timer then
        return
    end
    local time = rand(5, 10)
    state.save_timer = skynet.timeout(time * 100, db_save_handle)
end

----------------内部函数end

---开启写入定时器
function CMD.start_timer()
    start_timer()
end

---写入db
function CMD.db_save(conf, tab, index, data)
    -- log_print(conf, tab, index)
    if state.wait_map[tab] then
        state.wait_map[tab][index] = {conf = conf, data = data}
    else
        state.wait_map[tab] = {[index] = {conf = conf, data = data}}
    end
    start_timer()
end

---删除db
function CMD.db_delete(conf, tab, index, args)
    if args.type == 2 then
        if state.wait_del_map[tab] then
            state.wait_del_map[tab]["all"][args.key] = {key = args.key, conf = conf, indexs = args.indexs}
        else
            state.wait_del_map[tab] = {["all"] = {[args.key] = {key = args.key, conf = conf, indexs = args.indexs}}}
        end
    else
        if state.wait_del_map[tab] then
            state.wait_del_map[tab]["index"][index] = {key = args.key, conf = conf}
        else
            state.wait_del_map[tab] = {["index"] = {[index] = {key = args.key, conf = conf}}}
        end     
    end
    start_timer()
end

---清表
function CMD.db_truncate(conf, tab, type)
    state.wait_truncate_map[tab] = {conf = conf, type = type}
    start_timer()
end

skynet.start(function()
    InitCache()
    --服务的消息处理
    skynet.dispatchex("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(q, f, ...)
        if not status then
            log_print("cache_mgr service err:", f, err)
        end
    end)
end)