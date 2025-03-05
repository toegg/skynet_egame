local skynet = require "skynetex"
local cluster = require "skynet.cluster"
require "skynet.manager"
require "common.etool"
local clusters_api = require "clusters.clusters_api"
local datacenter = require "skynet.datacenter"
local commonFunc = require "common.func"

--连接的游戏服节点
local nodes = {}
--节点检测心跳包时间(30s)
local heart_time = 30
local heart_timer = nil
local heart_limit_times = 3

--分发指令
local CMD = {}

--节点检测心跳包
function heart_check()
    if table_len(nodes) > 0 then
        heart_timer = skynet.timeout(heart_time * 100, heart_check)
    end
    for k, v in pairs(nodes) do
        --检测上次发送是否还没响应，+1累计次数，达到则断开连接
        if v.heart_check == true then
            v.heart_timeout_times = v.heart_timeout_times + 1
        end
        if v.heart_timeout_times >= heart_limit_times then
            nodes[v.node] = nil
            remove_server_info(v.server_id)
            log_print( "Built disconnected to cluster node ", v.node)
            clusters_api.center_disconnect(v)
        else
            --设置检测标志位
            v.heart_check = true
            clusters_api.apply(v.node, v.fd, "center_heart_check", skynet.self())
        end
    end
end
--------------内部方法（异步操作）
--游戏服心跳包检测响应
function CMD.heart_check_callback(node)
    if nodes[node] then
        --移除检测标志位
        nodes[node].heart_check = false
    end
end

--游戏服连接上跨服，添加游戏节点记录
function CMD.add_node(game_node)
    if game_node == nil then
        return 
    end
    --检测跟已有的节点信息的node和server_id是否一致,不一致才更新
    local check_ret, check_ret1, check_ret2 = nil, nil, nil
    if nodes[game_node.node] and nodes[game_node.node].server_id == game_node.server_id then
        check_ret1 = false
    elseif nodes[game_node.node] then
        check_ret1 = true
    else
        check_ret1 = true
    end
    local old_node = clusters_api.get_server_info(game_node.server_id)
    if old_node and old_node.node == game_node.node then
        check_ret2 = false
    elseif old_node then
        check_ret2 = true
    else
        check_ret2 = true
    end
    check_ret = check_ret1 or check_ret2

    if check_ret then
        nodes[game_node.node] = game_node
        set_server_info(game_node)
        clusters_api.apply(game_node.node, game_node.node, "connected", skynet.self())
        clusters_api.center_connect(game_node)
    end

    --开启心跳包检测
    if table_len(nodes) > 0 then
        if not (type(heart_timer) == "thread") then
            heart_timer = skynet.timeout(heart_time * 100, heart_check) 
        end
    end
end

--通知所有节点执行
function CMD.apply_to_all_node(mod, f, ...)
    for i, v in pairs(nodes) do
        clusters_api.apply(v.node, mod, f, ...)
    end
end

--跨服执行func
function CMD.func_handle(funcName, ...)
    if commonFunc[funcName] then
        local f = commonFunc[commonFunc[funcName]]
        local status, err = pcall(f, ...)
        if not status then
            log_print("func_hanlde Err:", err)
        end
    else
        log_print("func_handle NOT EXITS")
    end
end
--------------内部方法（同步操作）

--------------初始化服务
function CMD.init()
    log_print("cluster node init")
    local node_list = parse_node_list()
    if table_len(node_list) > 0 then
        --开启集群
        cluster.reload(node_list)
        local node = skynet.getenv("node")
        cluster.open(node)
        --全局名字注册
        skynet.name(node, skynet.self())
    else
        log_print("cluster node_list Miss")
        skynet.exit()
    end
end

function parse_node_list()
    local node_list_str = skynet.getenv("node_list")
    local node_list1 = spilt(node_list_str, ";")
    local list = {}
    for k, v in pairs(node_list1) do
        local res = spilt(v, "-")
        if #res == 2 then
            list[res[1]] = res[2]
        end
    end
    -- print_table(node_list)
    return list
end

function CMD.test(...)
    log_print("test!!!!!!!!!!!!!!!!2222222222!")
end

--------------启动服务
skynet.start(function()
    --服务的消息处理
    skynet.dispatchex("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(f, ...)
        if not status then
            log_print("cluster node err:", f, err)
        end
    end)

    --收集info信息
    skynet.info_func(function()
        return nodes
    end)
end)

--------------内部调用函数
--设置节点信息缓存
function set_server_info(game_node)
    datacenter.set("nodes", nodes)
    datacenter.set("node_info", game_node.server_id, game_node)
end

--移除节点信息缓存
function remove_server_info(server_id)
    datacenter.set("nodes", nodes)
    datacenter.set("node_info", server_id, nil)
end