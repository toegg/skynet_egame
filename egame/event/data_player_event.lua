--该模块需要手动配置

require "common.misc"
require "def.def_event"

function get_events(event)
    if event == EVENT_LOGIN then
        return event_login()
    elseif event == EVENT_LV then
        return event_lv()
    elseif event == EVENT_ENTER_DUN then
        return event_enter_dun()
    elseif event == EVENT_DELAY_LOGOUT then
        return event_delay_logout()
    elseif event == EVENT_LOGOUT then
        return event_logout()
    elseif event == EVENT_RECONNECT then
        return event_reconnect()
    ---新增...
    end
end

--登录事件
function event_login()
    local list = {}
    list["player.player_handle"] = "handle_event"
    ---新增...
    return list
end

--升级事件
function event_lv()
    local list = {}
    ---新增...
    return list
end

--进入副本事件
function event_enter_dun()
    local list = {}
    ---新增...
    return list
end

--延迟登出事件
function event_delay_logout()
    local list = {}
    ---新增...
    return list
end

--登出事件
function event_logout()
    local list = {}
    ---新增...
    return list
end

--重连 
function event_reconnect()
    local list = {}
    ---新增...
    return list
end