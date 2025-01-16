local skynet = require "skynet"
require "skynet.manager"

skynet.start(function()
    --初始化数据服务
    skynet.newservice("server/server_init")

    --debug服务
    skynet.newservice("debug_console", skynet.getenv("debug_console"))

    --启动本地节点服务
    local node = skynet.newservice("clusters/clusters_node")
    skynet.send(node, "lua", "init")

    --启动客户端socket连接服务
    skynet.newservice("listen/socketlisten")

    --测试
    -- local test = skynet.newservice("etest")
    -- skynet.send(test, "lua", "start")

    skynet.exit()
end)