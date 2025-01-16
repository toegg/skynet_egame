local skynet = require "skynet"
require "skynet.manager" 

local misc = {}

--注册玩家进程
function misc.register_role_fd(player, role_id)
    skynet.name(misc.get_role_fd_name(role_id), player)
end

--获取玩家的进程fd
function misc.get_role_fd(role_id)
    return skynet.localname(misc.get_role_fd_name(role_id))
end

--获取玩家进程名字
function misc.get_role_fd_name(role_id)
    return ".role_progress"..tostring(role_id)
end

--注册玩家物品进程
function misc.register_goods_fd(goods, role_id)
    skynet.name(misc.get_goods_fd_name(role_id), goods)
end

--获取玩家物品进程fd
function misc.get_goods_fd(role_id)
    return skynet.localname(misc.get_goods_fd_name(role_id))
end

--获取玩家物品进程名字
function misc.get_goods_fd_name(role_id)
    return ".role_goods"..tostring(role_id)
end

return misc