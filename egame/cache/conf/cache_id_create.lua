local cache = {}

function cache.tables()
    return {"id_create"}
end

function cache.table(tab)
    if tab == "id_create" then
        return {
            ["main_index"] = "type",
            ["index"] = {"type"},
            ["field"] = {"type", "count"},
            ["json"] = {}
        }       
    end
    return nil
end

return cache