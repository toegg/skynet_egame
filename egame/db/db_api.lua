local skynet = require "skynet"
local db = {}

function db.query(sql)
    local pid = skynet.localname(".db")
    local res = skynet.call(pid, "lua", "handle", sql)
    return res
end

return db