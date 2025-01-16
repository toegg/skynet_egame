local skynet = require "skynet"
local datacenter = require "skynet.datacenter"
local cluster = require "skynet.cluster"
require "common.etool"

local api = {}

--跨服中心与游戏服节点连接（在跨服中心执行）
function api.center_connect(game_node)
    log_print("center_connect", game_node.node)
end

--跨服中心与游戏服的连接断开（跨服中心执行）
function api.center_disconnect(game_node)
    log_print("center_disconnect", game_node.node)
end

--游戏服节点连接上跨服中心（在游戏服执行）
function api.node_connect(pid)
    log_print("node_connect", pid)
end

--是否跨服中心节点
function api.is_center()
    return skynet.getenv("cls_type") == 1
end

--跨服中心节点和游戏服节点的异步调用
function api.apply(node, mod, f, ...)
    if node == nil then
        apply_to_local(mod, f, ...)
    elseif type(node) == "number" then
        if skynet.getenv("node") == node then
            apply_to_local(mod, f, ...)
        else
            local node = clusters_api.get_node(node)
            if node ~= nil then
                apply_to_other_node(node, mod, f, ...)
            end
        end
    else
        if skynet.getenv("node") == node then
            apply_to_local(mod, f, ...)
        else
            apply_to_other_node(node, mod, f, ...)
        end       
    end
end

function apply_to_local(mod, f, ...)
    if mod == nil then
        f(...)
    else
        skynet.send(mod, "lua", f, ...)
    end   
end

function apply_to_other_node(node, mod, f, ...)
    if mod == nil then
        cluster.send(node, node, f, ...)
    else
        cluster.send(node, mod, f, ...)
    end
end

--跨服中心获取游戏服信息
function api.get_server_info(server_id)
    local game_node = datacenter.get("nodes", server_id)
    if type(game_node) == "table" then
        return game_node
    end
    return nil
end

--跨服中心获取游戏服节点node
function api.get_node(server_id)
    local info = api.get_server_info(server_id)
    if info then
        return info.node
    end
    return nil
end

return api