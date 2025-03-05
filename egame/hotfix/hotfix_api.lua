--全局方法，local方法类型
local typeReloadGlobal, typeReloadLocal = 1, 2
local reloadInfo = {
    type = nil,     --热更的方法类型
    m = nil,        --local方法的模块名
    f = nil         --local方法的方法名
}


local _P = _P or {}
local CMD = _P.lua.CMD

--下面例子是center_main.lua启动了test服务，每1秒调用etool的全局方法etool_test和player_handle.cmd_handle方法

--local方法的热更
local local_script_str = [[
    local player_handle = require "player.player_handle"
    function func(cmd, data)
        if cmd == 10001 then 
            --登录
            player_login(cmd, data)
        elseif cmd == 10002 then  
            --注册
            player_reg(cmd, data)
        elseif cmd == 10010 then  
            --测试
            net.write(cmd, data)
        elseif cmd == 10011  then
            if player_handle.count then
                player_handle.count = player_handle.count + 1
            else
                player_handle.count  = 1
            end
            log_print("print count reload", player_handle.count)
        end
    end
    return func
]]
CMD.reloads[local_script_str] = {type = typeReloadLocal, m = "player.player_handle", f = "cmd_handle"}


--全局方法的热更
local global_script_str = [[
    function etool_test(val)
        log_print("etool_test reload:", val)
    end
]]
CMD.reloads[global_script_str] = {type = typeReloadGlobal}
