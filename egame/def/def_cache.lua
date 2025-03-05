BASE_CACHE = {
    type = nil,
    conf = nil,
    fd = nil
}

BASE_CACHE_MGR = {
    caches = nil,
    wait_map = nil,     --等待写入的tab
    wait_del_map = nil, 
    wait_truncate_map = nil,
    write_map = nil,    --正在写入的tab
    del_map = nil,      --正在删除的tab
    save_timer = nil    --写入db的定时器
}

BASE_CACHE_STATE = {
    type = nil,
    conf = nil,
    datas = nil,
    datas_index = nil,
    db_waits = nil,         --等待写入的sql
    db_del_waits = nil,     --等待删除的sql
    db_truncate_waits = nil,--等待清表的sql
    gc_delay_times = nil
}