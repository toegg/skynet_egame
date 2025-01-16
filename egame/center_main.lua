local skynet = require "skynet"
require "skynet.manager"

skynet.start(function()
    --初始化数据服务
    skynet.newservice("server/cluster_init")

    --debug服务
    skynet.newservice("debug_console", skynet.getenv("debug_console"))

    --启动跨服中心节点
    local center = skynet.newservice("clusters/clusters_center")
    skynet.send(center, "lua", "init")

    --测试
    -- local test = skynet.newservice("test/test")
    -- skynet.send(test, "lua", "init")
    skynet.exit()
end)