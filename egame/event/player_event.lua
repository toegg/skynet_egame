local skynet = require "skynetex"
require "def.def_event"
require "event.data_player_event"
require "common.etool"

local role_event = {
    event_list = {}
}

function role_event.register_event(event, mod, func)
    if event <= 0 then
        return
    end
    
    local list = role_event.event_list[event] or {}
    if list[mod] == nil then
        list[mod] = func
        role_event.event_list[event] = list
    end
end

function role_event.unregister_event(event, mod) 
    if event <= 0 then
        return
    end

    local list = role_event.event_list[event] or {} 
    list[mod] = nil
    role_event.event_list[event] = list
end

function role_event.event_dispatch(event, ...)
    if event <= 0 then
        return
    end

    if role_event.event_list[event] then
        for k, v in pairs(role_event.event_list[event]) do
            if type(k) ~= "number" then
                local k = skynet.load(k)
                local f = k[v]
                if type(f) == "function" then
                    f(event, ...)
                end
            else
                skynet.send(k, "lua", v, event, ...)
            end
        end
    end
end

function role_event.init_event(role_id)
    for k, v in pairs(EVENT_LIST) do
         local list = get_events(v, role_id)
         if table_len(list) > 0 then
             role_event.event_list[v] = list
         end
    end 
 end

return role_event