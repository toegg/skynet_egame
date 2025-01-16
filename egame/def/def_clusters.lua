BASE_CLUSTERS_NODE = {
    center_node = nil,
    node = nil,
    fd = nil,
    server_id = nil,
    conn_times = nil,
    conn_timer = nil,   --连接跨服中心定时器
    pid = nil,          --跨服中心管理进程fd
    conn_worker = nil,  --尝试连接跨服中心的协程
    wait_conn = false   
}

BASE_GAME_NODE = {
    node = nil,
    server_id = nil,
    fd = nil,
    heart_check = nil,
    heart_timeout_times = nil
}