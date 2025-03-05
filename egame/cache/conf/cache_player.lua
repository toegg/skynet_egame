local cache = {}

function cache.tables()
    return {"player"}
end

function cache.table(tab)
    if tab == "player" then
        return {
            ["main_index"] = "role_id",
            ["index"] = {"role_id"},
            ["field"] = {"role_id", "name"},
            ["json"] = {}
        }       
    end
    return nil
end

return cache