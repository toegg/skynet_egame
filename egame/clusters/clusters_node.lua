local skynet = require "skynetex"
local cluster = require "skynet.cluster"
local harbor = require "skynet.harbor"
require "skynet.manager"
require "common.etool"
local clusters_api = require "clusters.clusters_api"
require "def.def_clusters"

--分发指令
local CMD = {}

--定时器时间(10s)
local reconnect_time = 2 * 100

--跨服本地服节点的连接管理进程状态数据
local clusters_node = BASE_CLUSTERS_NODE

--------------与跨服中心建立连接(跨服中心回调)
function CMD.connected(pid)
    if clusters_node.pid == nil then
        clusters_node.pid = pid
        clusters_node.wait_conn = false
        clusters_api.node_connect(pid)
    end
end

--------------与跨服中心断开连接(跨服中心回调)
function CMD.disconnected()
    if clusters_node.pid then
        log_print("disconnected center")
        clusters_node.pid = nil 
        clusters_node.wait_conn = true
        try_to_conn_center()
    end
end
--------------跨服中心的心跳包检测
function CMD.center_heart_check(pid)
    if clusters_node.pid ~= nil then
        clusters_api.apply(clusters_node.center_node, clusters_node.pid, "heart_check_callback", clusters_node.node)
    end
end

--------------异步调用跨服中心
function CMD.apply_to_center(mod, f, ...)
    if clusters_node.pid ~= nil then
        if mod == nil then
            mod = clusters_node.center_node
        end
        clusters_api.apply(clusters_node.center_node, mod, f, ...) 
    end
end

--------------初始化服务
function CMD.init()
    log_print("game node init")
    local node_list = parse_node_list()
    if table_len(node_list) > 0 then
        --开启集群
        cluster.reload(node_list)
        local node = skynet.getenv("node")
        cluster.open(node)
        --全局名字注册
        skynet.name(node, skynet.self())
        -- 初始进程信息
        clusters_node.center_node = skynet.getenv("center_node")
        clusters_node.node = node
        clusters_node.fd = skynet.self()
        clusters_node.server_id = skynet.getenv("server_id")
        clusters_node.conn_times = 0
        clusters_node.conn_timer = try_to_conn_center()
        clusters_node.wait_conn = true
        clusters_node.conn_worker = skynet.fork(conn_center)
        -- 测试远程消息
        clusters_api.apply("center_node", "center_node", "test")
    else
        log_print("game node_list Miss")
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
    return list
end

--------------协程连接跨服节点
function conn_center() 
    while true do
        skynet.wait()
        --可能跨服节点还没起来，要捕捉异常，防止当前协程崩了
        local status, err = skynet.pcall(function()
            harbor.queryname(clusters_node.center_node)
        end)
        if status then
            log_print("apply center add node")
            local game_node = {
                node = clusters_node.node, 
                server_id = clusters_node.server_id, 
                fd = clusters_node.fd,
                heart_check = false,
                heart_timeout_times = 0
            }
            clusters_api.apply(clusters_node.center_node, clusters_node.center_node, "add_node", game_node)
        end 
    end
end

--------------连接跨服节点
function try_to_conn_center()
    skynet.timeout(reconnect_time, function()
        if clusters_node.pid == nil then
            clusters_node.wait_conn = false
            clusters_node.conn_times = clusters_node.conn_times + 1
            try_to_conn_center()
        end
    end)
    if clusters_node.wait_conn == false then
        local status, err = skynet.pcall(skynet.wakeup, clusters_node.conn_worker)
        if not status then
            log_print("cluster node err:", err)
        end       
    end
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
end)