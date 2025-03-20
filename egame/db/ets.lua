local skynet = require "skynet"
local ets_cache = require "etscache"
local sharedata = require "skynet.sharedata"
require "common.etool"

local ets = {}

local function create_ets()
    local status, ets_ref = skynet.pcall(sharedata.query, "ets_ref")
    if status and ets_ref and ets_ref.ref then
        return ets_ref.ref
    end
    local ets_table = ets_cache.create()
    sharedata.update("ets_ref", {ref = ets_table})
    return ets_table
end

ets.ets_table = ets.ets_table or create_ets()

function ets.init(name)
    return ets_cache.init(name)
end

function ets.insert(name, key, value)
    return ets_cache.insert(name, key, value)
end

function ets.lookup(name, key)
    return ets_cache.lookup(name, key)
end

function ets.delete(name, key)
    return ets_cache.delete(name, key)
end

function ets.delete_all(name)
    return ets_cache.delete_all(name)
end

return ets