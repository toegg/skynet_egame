--redis用hash存储

--key主要有4种：

----第一种：对应的主键
--key:index_表名, field:main_index, val:indexList
----其中main_index一般是主键，而联合主键的main_index就是联合主键中的主要字段，比如玩家对应多条装备数据，则用玩家id作为main_index  
----indexList则是对应的主键列表，用table格式序列化成json

----第二种：主键对应具体数据
--key:rec_表名, field:index, val:表行所有数据

----第三种：脏数据，待写入mysql
--key:dirty_表名，field:index, val:1(删除);0(写入)

----第四种：清表
--key:dirty_truncate_all, field:表名, val:清除类型1(truncate);0(delete)

local skynet = require "skynetex"
local queue = require "skynet.queue"
require "skynet.manager"
local cjson = require "cjson"
require "cache.cache_config"
local db = require "db.db_api"
local rd = require "db.rd_api"
require "common.etool"
require "def.def_cache"
require "def.def_error"

local state = BASE_CACHE_STATE
local type, conf = ...
--表配置
local config = {}

--检测脏数据时间
local check_dirty_time = nil

local q = queue()
local CMD = {}

----------------内部函数
--pipe是否全成功
local function pipleline_ok(len, res)
    if not res.data then
        return false
    end
    local num = 0
    for k, v in pairs(res.data) do
        if v["ok"] then
            num = num + 1
        end
    end
    return num == len
end

--通知mgr处理脏数据
local function handle_dirty()
    --通知管理进程写入，写入都通过mgrFd写，串行
    local mgrFd = skynet.localname(".cache_mgr")
    local now = math.floor(skynet.time())
    for k, v in pairs(state.db_waits) do
        for kk, vv in pairs(v) do
            --未同步或已同步时间大于60s，再同步一次
            if vv.is_sync == 0 or vv.sync_time < now - 60 then
                skynet.send(mgrFd, "lua", "db_save", conf, k, kk, vv.data)
                vv.is_sync = 1
                vv.sync_time = now 
            end
        end
    end
    --通知管理进程删除
    for k, v in pairs(state.db_del_waits) do
        for kk, vv in pairs(v) do
            --未同步或已同步时间大于60s，再同步一次
            if vv.is_sync == 0 or vv.sync_time < now - 60 then
                local args = {}
                args["key"] = vv.key
                args["type"] = vv.type
                if vv.type == 2 then
                    args["indexs"] = state.datas_index[k][vv.key]
                end
                skynet.send(mgrFd, "lua", "db_delete", conf, k, kk, args)
                vv.is_sync = 1
                vv.sync_time = now 
            end
        end   
    end
    --通知管理进程清表
    for k, v in pairs(state.db_truncate_waits) do
        --未同步或已同步时间大于60s，再同步一次
        if v.is_sync == 0 or v.sync_time < now - 60 then
            skynet.send(mgrFd, "lua", "db_truncate", conf, k, v.type)
            v.is_sync = 1
            v.sync_time = now 
        end 
    end
end

--检测脏数据
local function check_dirty()
    skynet.timeout(check_dirty_time * 100, check_dirty)
    handle_dirty()
end

--初始化
local function InitCache()
    skynet.name("."..conf, skynet.self())
    config = skynet.load(conf)
    --初始数据
    state.type = type
    state.conf = conf
    state.datas = {}
    state.datas_index = {}
    state.db_waits = {}
    state.db_del_waits = {}
    state.db_truncate_waits = {}
    state.gc_delay_times = 0
    for k, v in pairs(config.tables()) do
        state.datas[v] = {}
        state.datas_index[v] = {}
        state.db_waits[v] = {}
        state.db_del_waits[v] = {}
    end
    check_dirty_time = rand(1, 6)
    skynet.timeout(check_dirty_time * 100, check_dirty)
end

--读取redis和db
local function fetch(tab, key)
    local datas = {}
    --先读取redis，hash的key： index_tab变量, 再读取rec_tab变量，最后读取dirty_tab变量
    local res = rd.query("hget", "index_"..tab, key)
    local indexsJson = res.data
    if indexsJson then
        print_table(indexsJson)
        local indexs = cjson.decode(indexsJson)
        state.datas_index[tab][key] = indexs
        for k, v in pairs(indexs) do
            res = rd.query("hget", "rec_"..tab, v)
            local resJson = res.data
            if resJson then
                local data = cjson.decode(resJson)
                state.datas[tab][v] = data
                table.insert(datas, data)
                --看是否有脏数据
                res = rd.query("hget", "dirty_"..tab, v)
                if res.data then
                    state.db_waits[tab][v] = {data = data, time = math.floor(skynet.time()), is_sync = 0, sync_time = 0}
                end
            end
        end
    else
        --不存在index_tab变量，读取db
        local tabInfo = config.table(tab)
        local result = db.query(string.format("select * from %s where %s = %s", tab, tabInfo["main_index"], key))
        if result.err == nil and #result > 0 then
            local indexs = {}
            local tempData = {}
            for k, v in pairs(result) do
                --解析json的字段
                for kk, vv in pairs(tabInfo["json"]) do
                    if v[vv] then
                        local status, err = pcall(function()
                            v[vv] = cjson.decode(v[vv]) 
                        end)
                        if not status then
                            log_print("err", err)
                        end
                    end
                end
                --获取主键值
                local index = {}
                for kk, vv in pairs(tabInfo["index"]) do
                    table.insert(index, v[vv])
                end
                if #index > 0 then
                    local indexJson = cjson.encode(index)
                    table.insert(indexs, indexJson) 
                    tempData[indexJson] = v
                end
            end
            --1. 先事务写redis
            local pipe = {
                {"multi"},
                {"hset", "index_"..tab, key, cjson.encode(indexs)}
            }
            for k, v in pairs(indexs) do
                table.insert(pipe, {"hset", "rec_"..tab, v, cjson.encode(tempData[v])})
            end
            table.insert(pipe, {"exec"})
            local res = rd.query("pipeline", pipe, {})
            if pipleline_ok(#pipe, res) then
                --2. 再更新state.datas内存
                state.datas_index[tab][key] = indexs
                for k, v in pairs(tempData) do
                    state.datas[tab][k] = v
                    table.insert(datas, v)
                end 
            end
        elseif result.err ==nil then
            res = rd.query("hset", "index_"..tab, key, cjson.encode({}))
            if not res.err then
                state.datas_index[tab][key] = {}
            end
        else
            log_print("sql Err:", result.err)
        end
    end
    return datas
end

--gc 缓存和redis数据
local function gc_data_handle(tab)
    if table_len(state.datas_index[tab]) <= 0 then
        return
    end

    local remove_keys = {}
    local pipe = { 
        {"multi"},
    }
    for k, v in pairs(state.datas_index[tab]) do
        if #remove_keys > 50 then
            break
        end
        table.insert(remove_keys, k)
        --为空的不处理，继续存着
        if #v > 0 then
            table.insert(pipe, {"hdel", "index_"..tab, k})
            for kk, vv in pairs(v) do
                table.insert(pipe, {"hdel", "rec_"..tab, vv})
                table.insert(pipe, {"hdel", "dirty_"..tab, vv})
            end 
        end
    end
    table.insert(pipe, {"exec"})
    local res = rd.query("pipeline", pipe, {})
    --每50个一个事务提交
    if pipleline_ok(#pipe, res) then
        for k, v in pairs(remove_keys) do
            for kk, vv in pairs(state.datas_index[tab][v]) do
                state.datas[tab][vv] = nil
            end
            state.datas_index[tab][v] = nil
        end
    end
    if table_len(state.datas_index[tab]) > 0 then
        gc_data_handle(tab)
    end
end

----------------内部函数end

----------------message处理
--读取
function CMD.fetch(tab, key)
    local res = {}
    if state.datas_index[tab] then
        local indexs = state.datas_index[tab][key]
        if indexs then
            for k, v in pairs(indexs) do
                if state.datas[tab][v] then
                    table.insert(res, state.datas[tab][v])
                end
            end
        else
            --读取redis和db
            local fetchRes = fetch(tab, key)
            res = fetchRes or {}
        end
    end
    skynet.ret(skynet.pack(res))
end

--写入
function CMD.replace(tab, data)
    if state.datas_index[tab] then
        local tabInfo = config.table(tab)
        local main_index = data[tabInfo["main_index"]]
        if not main_index then
            skynet.ret(skynet.pack(ERROR_INDEX_MISS))
            return
        end
        local index = {}
        for k, v in pairs(tabInfo["index"]) do
            if not data[v] then
                skynet.ret(skynet.pack(ERROR_INDEX_MISS))
                return
            end 
            table.insert(index, data[v])
        end
        index = cjson.encode(index)
        local indexs = state.datas_index[tab][main_index]

        --1.事务写入redis
        local pipe = { 
            {"multi"},
            {"hset", "dirty_"..tab, index, 0}
        }
        if indexs then
            if not indexs[index] then
                indexs = table.insert(indexs, index)
                table.insert(pipe, {"hset", "index_"..tab, main_index, cjson.encode(indexs)})
            end
        end
        table.insert(pipe, {"hset", "rec_"..tab, index, cjson.encode(data)})
        table.insert(pipe, {"exec"})
        local res = rd.query("pipeline", pipe, {})
        if pipleline_ok(#pipe, res) then
            --2.再更新state.datas内存
            state.datas_index[tab][main_index] = indexs
            state.datas[tab][index] = data
            state.db_waits[tab][index] = {data = data, time = math.floor(skynet.time()), is_sync = 0, sync_time = 0}
            skynet.ret(skynet.pack(ERROR_SUCCESS))
        else
            skynet.ret(skynet.pack(ERROR_REDIS_ERR))
        end
        return
    end
    skynet.ret(skynet.pack(ERROR_FAIL))
end

--删除
function CMD.delete(tab, key, index)
    local result = ERROR_FAIL
    if state.datas_index[tab] then
        local indexs = state.datas_index[tab][key]
        if not indexs then
            fetch(tab, key)        
        end
        if indexs then
            if index == "all" then
                local pipe = { {"multi"}}
                for k, v in pairs(indexs) do  
                    table.insert(pipe, {"hset", "dirty_"..tab, v, 1})        
                end
                table.insert(pipe, {"exec"})
                local res = rd.query("pipeline", pipe, {})
                if pipleline_ok(#pipe, res) then 
                    for k, v in pairs(indexs) do
                        state.db_del_waits[tab][v] = {key = key, type = 2, is_sync = 0, sync_time = 0} 
                    end
                    result = ERROR_SUCCESS
                else
                    log_print(res)
                end 
            else 
                if is_in_table(indexs, cjson.encode(index)) then
                    index = cjson.encode(index)
                    local res = rd.query("hset", "dirty_"..tab, index, 1)
                    if not res.err then
                        state.db_del_waits[tab][index] = {key = key, type = 1, is_sync = 0, sync_time = 0} 
                        result = ERROR_SUCCESS
                    end
                else
                    result = ERROR_SUCCESS 
                end
            end
        end
    end
    skynet.ret(skynet.pack(result))
end

--清除所有
function CMD.delete_all(tab, type)
    if not state.db_truncate_waits[tab] then
        local res = rd.query("hset", "dirty_truncate_all", tab, type)
        if not res.err then
            state.db_truncate_waits[tab] = {type = type, is_sync = 0, sync_time = 0} 
            skynet.ret(skynet.pack(true))
            return
        end  
    end
    skynet.ret(skynet.pack(false))
end

--mgr完成写入通知
function CMD.finish_db_save(tab, index)
    -- log_print(index)
    if state.db_waits[tab] then
        local info = state.db_waits[tab][index]
        if info then
            local res = rd.query("hdel", "dirty_"..tab, index)
            if not res.err then
                state.db_waits[tab][index] = nil 
            else
                log_print("finish_db_save Err", tab, index, res) 
            end
        end
    end
end

--mgr完成移除通知
function CMD.finish_db_del(tab, index, type, args)
    if not state.db_del_waits[tab] then
        return 
    end
    local indexs = args.indexs
    if type == 2 then
        local pipe = { 
            {"multi"}
        }
        if indexs then
            for k, v in pairs(indexs) do
                table.insert(pipe, {"hdel", "dirty_"..tab, v})
                table.insert(pipe, {"hdel", "rec_"..tab, v}) 
            end
        end
        table.insert(pipe, {"hset", "index_"..tab, args.key, cjson.encode({})})
        table.insert(pipe, {"exec"})
        local res = rd.query("pipeline", pipe, {})
        if pipleline_ok(#pipe, res) then 
            for k, v in pairs(indexs) do
                state.datas[tab][k] = nil
                state.db_del_waits[tab][k] = nil
            end 
            state.datas_index[tab][args.key] = {}
        end
    else
        indexs = state.datas_index[tab][args.key]
        index = cjson.encode(index)
        local pipe = { 
            {"multi"},
            {"hdel", "dirty_"..tab, index},
            {"hdel", "rec_"..tab, index}
        }
        if indexs then
            indexs = remove_in_table(indexs, index)
            table.insert(pipe, {"hset", "index_"..tab, args.key, cjson.encode(indexs)})
        end
        table.insert(pipe, {"exec"})
        local res = rd.query("pipeline", pipe, {})
        if pipleline_ok(#pipe, res) then 
            state.db_del_waits[tab][index] = nil
            if state.datas_index[tab][args.key] then
                for k, v in pairs(state.datas_index[tab][args.key]) do
                    state.datas[tab][k] = nil
                end  
            end
            state.datas_index[tab][args.key] = indexs
        else
            print_table(res)
        end
    end
end

---mgr完成清表通知
function CMD.finish_db_truncate(tab)
    if state.db_truncate_waits[tab] then
        local pipe = { 
            {"multi"},
            {"hdel", "dirty_truncate_all", tab},
            {"del", "dirty_"..tab},
            {"del", "rec_"..tab},
            {"del", "index_"..tab},
            {"exec"}
        }    
        local res = rd.query("pipeline", pipe, {})
        if pipleline_ok(#pipe, res) then
            state.db_truncate_waits[tab] = nil
            state.datas[tab] = {}
            state.datas_index[tab] = {}
        else
            print_table(res)
        end
    end
end

--mgr通知gc数据
function CMD.gc_data()
    local has_dirty = nil
    for k, v in pairs(state.db_waits) do
        if table_len(v)> 0 then
            has_dirty = true
        end
    end
    if has_dirty then
        --达到20次则不处理了
        if state.gc_delay_times >= 20 then
            return
        end
        handle_dirty()
        skynet.timeout(30 * 100, CMD.gc_data)
        state.gc_delay_times = state.gc_delay_times + 1
    else
        state.gc_delay_times = 0
        for k, v in pairs(state.datas_index) do
            gc_data_handle(k)
        end
    end
end

----------------message处理end

skynet.start(function()
    InitCache()
    --服务的消息处理
    skynet.dispatchex("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(q, f, ...)
        if not status then
            log_print("cache service err:", f, err, type, conf)
        end
    end)

    --收集info信息
    skynet.info_func(function()
        return state
    end)
end)