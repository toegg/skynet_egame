-------该模块定义一些需要跨服务的函数方法
local skynet = require "skynet"

local func = {}

-- key：自定义；val：对应方法名
func["dun"] = "open_dun"

----开启副本
function func.open_dun(dun_id, room_id, role_list, dun_args)
    local dungeon = skynet.newservice("dungeon")
    skynet.send(dungeon, "lua", "init", dun_id, room_id, role_list, dun_args)
end

----新增...

return func