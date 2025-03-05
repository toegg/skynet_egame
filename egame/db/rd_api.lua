local skynet = require "skynet"
local rd = {}

--res格式：{data = data, err = err}
function rd.query(func, ...)
    local pid = skynet.localname(".rd")
    local res = skynet.call(pid, "lua", "handle", func, ...)
    return res
end

return rd