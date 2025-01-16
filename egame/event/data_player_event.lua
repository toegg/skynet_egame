--该模块需要手动配置

require "common.misc"
require "def.def_event"

function get_events(event, role_id)
    if event == EVENT_LOGIN then
        return event_login(role_id)
    elseif event == EVENT_LV then
        return event_lv(role_id)
    elseif event == EVENT_ENTER_DUN then
        return event_enter_dun(role_id)
    ---新增...
    end
end

--登录事件
function event_login(role_id)
    local list = {}
    list["player.player_handle"] = "handle_event"
    ---新增...
    return list
end

--升级事件
function event_lv(role_id)
    local list = {}
    ---新增...
    return list
end

--进入副本事件
function event_enter_dun(role_id)
    local list = {}
    ---新增...
    return list
end