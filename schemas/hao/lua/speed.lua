-- librime-lua
-- encoding: utf-8

-- 速度统计 - 基于实际上屏文字的统计（修复版本）

if not print then
    function print(...)
        if true then return end
        local t = {}
        for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end
        log.warning(table.concat(t, " "))
    end
end

local M = {}
M.init_flag = false

-- 数据文件路径
M.stats_file = rime_api.get_user_data_dir() .. "/speed_stats.conf"
M.data_dirty = false
M.last_save_time = os.time()

-- 会话超时时间（毫秒）
M.session_timeout = 2000  -- 改回2秒

-- 全局状态
if not gS then gS = {} end
gS.session_start = 0      -- 会话开始时间（毫秒）
gS.last_commit_time = 0   -- 最后上屏时间（毫秒）
gS.session_chars = 0      -- 会话字符数
gS.last_session_speed = 0 -- 上一次会话的速度
gS.last_session_chars = 0 -- 上一次会话的字数
gS.last_session_time = 0  -- 上一次会话的时间（秒）
gS.session_active = false -- 会话是否活跃
gS.has_previous_session = false -- 是否有上一次会话数据
gS.show_current_speed = false -- 是否显示当前速度

-- 字数统计数据
gS.char_stats = {
    daily = 0,   -- 今日输入
    monthly = 0, -- 本月输入
    yearly = 0,  -- 本年输入
    total = 0,   -- 总计输入
    last_update = os.date("*t")  -- 最后更新时间
}

-- 平均速度统计数据
gS.avg_speed_stats = {
    daily = {
        total_speed = 0,  -- 今日所有会话速度总和
        session_count = 0, -- 今日会话次数
        last_update = os.date("*t")  -- 最后更新时间
    },
    monthly = {
        daily_speeds = {}, -- 本月每日平均速度 {日期=速度}
        last_update = os.date("*t")  -- 最后更新时间
    },
    yearly = {
        monthly_speeds = {}, -- 本年每月平均速度 {月份=速度}
        last_update = os.date("*t")  -- 最后更新时间
    },
    total = {
        yearly_speeds = {}, -- 总计每年平均速度 {年份=速度}
        last_update = os.date("*t")  -- 最后更新时间
    }
}

-- 表序列化工具
table.serialize = function(tbl)
    local lines = {"{"}
    for k, v in pairs(tbl) do
        local key = (type(k) == "string") and ("[\"" .. k .. "\"]") or ("[" .. k .. "]")
        local val
        if type(v) == "table" then val = table.serialize(v)
        elseif type(v) == "string" then val = '"' .. v .. '"'
        else val = tostring(v) end
        table.insert(lines, string.format("    %s = %s,", key, val))
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

-- 保存数据到文件
function M.save_stats(force)
    if not M.data_dirty and not force then return end
    
    local current_time = os.time()
    if force or (current_time - M.last_save_time > 60) then -- 最多每分钟保存一次
        local file = io.open(M.stats_file, "w")
        if file then
            local data_to_save = {
                char_stats = gS.char_stats,
                last_session_speed = gS.last_session_speed,
                last_session_chars = gS.last_session_chars,
                last_session_time = gS.last_session_time,
                has_previous_session = gS.has_previous_session,
                avg_speed_stats = gS.avg_speed_stats  -- 保存平均速度数据
            }
            file:write("return " .. table.serialize(data_to_save) .. "\n")
            file:close()
            M.last_save_time = current_time
            M.data_dirty = false
        end
    end
end

-- 从文件加载数据
function M.load_stats()
    local ok, data = pcall(function()
        if not io.open(M.stats_file, "r") then return nil end
        return dofile(M.stats_file)
    end)
    
    if ok and data then
        if data.char_stats then
            -- 检查日期是否需要重置
            local current_date = os.date("*t")
            local last_date = data.char_stats.last_update or current_date
            
            -- 如果日期不同，重置相应的统计
            if current_date.year ~= last_date.year or 
               current_date.month ~= last_date.month or 
               current_date.day ~= last_date.day then
                data.char_stats.daily = 0
            end
            
            if current_date.year ~= last_date.year or 
               current_date.month ~= last_date.month then
                data.char_stats.monthly = 0
            end
            
            if current_date.year ~= last_date.year then
                data.char_stats.yearly = 0
            end
            
            data.char_stats.last_update = current_date
            gS.char_stats = data.char_stats
        end
        
        if data.last_session_speed then gS.last_session_speed = data.last_session_speed end
        if data.last_session_chars then gS.last_session_chars = data.last_session_chars end
        if data.last_session_time then gS.last_session_time = data.last_session_time end
        if data.has_previous_session then gS.has_previous_session = data.has_previous_session end
        
        -- 加载平均速度数据
        if data.avg_speed_stats then
            gS.avg_speed_stats = data.avg_speed_stats
        end
    end
end

-- 获取当前时间（毫秒）
function M.get_current_time_ms()
    if rime_api and rime_api.get_time_ms then
        return rime_api.get_time_ms()
    else
        -- 如果没有毫秒级时间，使用秒级时间乘以1000
        return os.time() * 1000
    end
end

-- 更新日期统计数据
function M.update_date_stats()
    local current_date = os.date("*t")
    local last_date = gS.char_stats.last_update
    
    -- 检查是否需要重置日统计
    if current_date.year ~= last_date.year or 
       current_date.month ~= last_date.month or 
       current_date.day ~= last_date.day then
        gS.char_stats.daily = 0
        M.data_dirty = true
        
        -- 重置日平均速度统计
        gS.avg_speed_stats.daily.total_speed = 0
        gS.avg_speed_stats.daily.session_count = 0
        gS.avg_speed_stats.daily.last_update = current_date
    end
    
    -- 检查是否需要重置月统计
    if current_date.year ~= last_date.year or 
       current_date.month ~= last_date.month then
        gS.char_stats.monthly = 0
        M.data_dirty = true
        
        -- 重置月平均速度统计
        gS.avg_speed_stats.monthly.daily_speeds = {}
        gS.avg_speed_stats.monthly.last_update = current_date
    end
    
    -- 检查是否需要重置年统计
    if current_date.year ~= last_date.year then
        gS.char_stats.yearly = 0
        M.data_dirty = true
        
        -- 重置年平均速度统计
        gS.avg_speed_stats.yearly.monthly_speeds = {}
        gS.avg_speed_stats.yearly.last_update = current_date
    end
    
    -- 更新最后更新时间
    gS.char_stats.last_update = current_date
    M.data_dirty = true
end

-- 更新平均速度统计数据
function M.update_avg_speed_stats(speed)
    local current_date = os.date("*t")
    local date_str = os.date("%Y-%m-%d")
    local month_str = os.date("%Y-%m")
    local year_str = tostring(current_date.year)
    
    -- 更新日平均速度
    gS.avg_speed_stats.daily.total_speed = gS.avg_speed_stats.daily.total_speed + speed
    gS.avg_speed_stats.daily.session_count = gS.avg_speed_stats.daily.session_count + 1
    gS.avg_speed_stats.daily.last_update = current_date
    
    -- 更新月平均速度（记录今日平均速度）
    local daily_avg = gS.avg_speed_stats.daily.session_count > 0 and 
                     math.floor(gS.avg_speed_stats.daily.total_speed / gS.avg_speed_stats.daily.session_count) or 0
    gS.avg_speed_stats.monthly.daily_speeds[date_str] = daily_avg
    gS.avg_speed_stats.monthly.last_update = current_date
    
    -- 更新年平均速度（记录本月平均速度）
    local monthly_total = 0
    local monthly_count = 0
    for _, speed_val in pairs(gS.avg_speed_stats.monthly.daily_speeds) do
        monthly_total = monthly_total + speed_val
        monthly_count = monthly_count + 1
    end
    local monthly_avg = monthly_count > 0 and math.floor(monthly_total / monthly_count) or 0
    gS.avg_speed_stats.yearly.monthly_speeds[month_str] = monthly_avg
    gS.avg_speed_stats.yearly.last_update = current_date  -- 修复了这里的拼写错误
    
    -- 更新总平均速度（记录本年平均速度）
    local yearly_total = 0
    local yearly_count = 0
    for _, speed_val in pairs(gS.avg_speed_stats.yearly.monthly_speeds) do
        yearly_total = yearly_total + speed_val
        yearly_count = yearly_count + 1
    end
    local yearly_avg = yearly_count > 0 and math.floor(yearly_total / yearly_count) or 0
    gS.avg_speed_stats.total.yearly_speeds[year_str] = yearly_avg
    gS.avg_speed_stats.total.last_update = current_date
    
    M.data_dirty = true
end

-- 计算平均速度
function M.calculate_avg_speed(period)
    if period == "daily" then
        return gS.avg_speed_stats.daily.session_count > 0 and 
               math.floor(gS.avg_speed_stats.daily.total_speed / gS.avg_speed_stats.daily.session_count) or 0
    elseif period == "monthly" then
        local total = 0
        local count = 0
        for _, speed_val in pairs(gS.avg_speed_stats.monthly.daily_speeds) do
            total = total + speed_val
            count = count + 1
        end
        return count > 0 and math.floor(total / count) or 0
    elseif period == "yearly" then
        local total = 0
        local count = 0
        for _, speed_val in pairs(gS.avg_speed_stats.yearly.monthly_speeds) do
            total = total + speed_val
            count = count + 1
        end
        return count > 0 and math.floor(total / count) or 0
    elseif period == "total" then
        local total = 0
        local count = 0
        for _, speed_val in pairs(gS.avg_speed_stats.total.yearly_speeds) do
            total = total + speed_val
            count = count + 1
        end
        return count > 0 and math.floor(total / count) or 0
    end
    return 0
end

-- 开始新会话
function M.start_new_session()
    local current_time_ms = M.get_current_time_ms()
    gS.session_start = current_time_ms
    gS.last_commit_time = current_time_ms
    gS.session_chars = 0
    gS.session_active = true
    gS.show_current_speed = false  -- 新会话开始时默认显示上次速度
end

-- 手动结束当前会话
function M.end_session_manually()
    if gS.session_active and gS.session_chars > 0 then
        local duration_ms = gS.last_commit_time - gS.session_start
        local duration_sec = duration_ms / 1000.0
        
        if duration_sec > 0 and gS.session_chars > 0 then
            gS.last_session_speed = math.floor((gS.session_chars / duration_sec) * 60 + 0.5)
            gS.last_session_chars = gS.session_chars
            gS.last_session_time = duration_sec
            gS.has_previous_session = true
            gS.show_current_speed = true  -- 会话正常结束时显示当前速度
            
            -- 更新平均速度统计数据
            M.update_avg_speed_stats(gS.last_session_speed)
            
            M.data_dirty = true
        else
            -- 如果会话无效（时间或字数为0），不更新上次会话数据
            gS.show_current_speed = false  -- 显示上次速度
        end
        
        -- 标记会话为非活跃
        gS.session_active = false
        
        -- 保存数据
        M.save_stats(true)
        
        return true
    end
    return false
end

-- 计算字符长度（包括英文、数字、标点和汉字）
function M.get_commit_length(text)
    if not text or text == "" then
        return 0
    end
    
    -- 直接返回字符数（包括英文、数字、标点和汉字）
    -- 使用utf8.codes来确保正确处理所有UTF-8字符
    local count = 0
    for _ in utf8.codes(text) do
        count = count + 1
    end
    return count
end

-- 更新速度统计数据
function M.update_stats(input_length)
    local current_time_ms = M.get_current_time_ms()
    
    -- 如果会话不活跃或超过2秒没有上屏，开始新会话
    if not gS.session_active or (current_time_ms - gS.last_commit_time > M.session_timeout) then
        -- 保存上一次会话数据
        if gS.session_active and gS.session_chars > 0 then
            local duration_ms = gS.last_commit_time - gS.session_start
            local duration_sec = duration_ms / 1000.0
            
            if duration_sec > 0 and gS.session_chars > 0 then
                gS.last_session_speed = math.floor((gS.session_chars / duration_sec) * 60 + 0.5)
                gS.last_session_chars = gS.session_chars
                gS.last_session_time = duration_sec
                gS.has_previous_session = true
                gS.show_current_speed = true  -- 会话正常结束时显示当前速度
                
                -- 更新平均速度统计数据
                M.update_avg_speed_stats(gS.last_session_speed)
                
                M.data_dirty = true
            else
                -- 如果会话无效（时间或字数为0），不更新上次会话数据
                gS.show_current_speed = false  -- 显示上次速度
            end
        end
        
        M.start_new_session()
    end
    
    -- 更新会话字符数和最后上屏时间
    gS.session_chars = gS.session_chars + input_length
    gS.last_commit_time = current_time_ms
    
    -- 更新字数统计数据
    M.update_date_stats()
    gS.char_stats.daily = gS.char_stats.daily + input_length
    gS.char_stats.monthly = gS.char_stats.monthly + input_length
    gS.char_stats.yearly = gS.char_stats.yearly + input_length
    gS.char_stats.total = gS.char_stats.total + input_length
    M.data_dirty = true
    
    -- 定期保存数据
    M.save_stats()
end

-- 检查会话是否结束并计算最终速度
function M.check_session_end()
    local current_time_ms = M.get_current_time_ms()
    
    -- 如果超过2秒没有上屏文字，会话结束（2000毫秒）
    if gS.session_active and (current_time_ms - gS.last_commit_time > M.session_timeout) then
        local duration_ms = gS.last_commit_time - gS.session_start
        local duration_sec = duration_ms / 1000.0
        
        -- 计算最终速度
        if duration_sec > 0 and gS.session_chars > 0 then
            gS.last_session_speed = math.floor((gS.session_chars / duration_sec) * 60 + 0.5)
            gS.last_session_chars = gS.session_chars
            gS.last_session_time = duration_sec
            gS.has_previous_session = true
            gS.show_current_speed = true  -- 会话正常结束时显示当前速度
            
            -- 更新平均速度统计数据
            M.update_avg_speed_stats(gS.last_session_speed)
            
            M.data_dirty = true
        else
            -- 如果会话无效（时间或字数为0），不更新上次会话数据
            gS.show_current_speed = false  -- 显示上次速度
        end
        
        -- 标记会话为非活跃
        gS.session_active = false
        
        -- 保存数据
        M.save_stats(true)
        
        return true
    end
    
    return false
end

-- 按键回调：检测编码输入和删除
local function key_event_callback(ctx, key)
    local key_repr = key:repr()
    
    -- 检测到字母键按下，标记为需要显示上次速度
    if key_repr:match("^[a-z]$") then
        gS.show_current_speed = false  -- 开始输入编码时显示上次速度
    -- 检测到退格键，也标记为需要显示上次速度
    elseif key_repr == "BackSpace" then
        gS.show_current_speed = false  -- 回改时显示上次速度
    end
    
    return false -- 不拦截按键
end

-- 格式化速度统计内容
function M.format_speed_summary()
    -- 检查会话是否结束
    M.check_session_end()
    
    if gS.session_active and gS.session_chars > 0 then
        local current_time_ms = M.get_current_time_ms()
        local duration_ms = current_time_ms - gS.session_start
        local duration_sec = duration_ms / 1000.0
        
        -- 计算当前速度
        local current_speed = 0
        if duration_sec > 0 then
            current_speed = math.floor((gS.session_chars / duration_sec) * 60 + 0.5)
        end
        
        return string.format("当前速度：%d字/分钟\n字数：%d\n时间：%.1f秒", 
                           current_speed, gS.session_chars, duration_sec)
    elseif gS.has_previous_session then
        -- 根据标志决定显示当前速度还是上次速度
        if gS.show_current_speed then
            return string.format("当前速度：%d字/分钟\n字数：%d\n时间：%.1f秒", 
                               gS.last_session_speed, gS.last_session_chars, gS.last_session_time)
        else
            return string.format("上次速度：%d字/分钟\n字数：%d\n时间：%.1f秒", 
                               gS.last_session_speed, gS.last_session_chars, gS.last_session_time)
        end
    else
        return "当前速度：0字/分钟\n字数：极速统计\n时间：0.0秒"
    end
end

-- 格式化字数统计内容
function M.format_char_stats_summary()
    M.update_date_stats()  -- 确保日期统计是最新的
    
    -- 计算各时间段的平均速度
    local daily_avg = M.calculate_avg_speed("daily")
    local monthly_avg = M.calculate_avg_speed("monthly")
    local yearly_avg = M.calculate_avg_speed("yearly")
    local total_avg = M.calculate_avg_speed("total")
    
    return string.format("今日输入：%d字 平均速度：%d字/分钟\n本月输入：%d字 平均速度：%d字/分钟\n本年输入：%d字 平均速度：%d字/分钟\n总计输入：%d字 平均极速：%d字/分钟",
                       gS.char_stats.daily, daily_avg,
                       gS.char_stats.monthly, monthly_avg,
                       gS.char_stats.yearly, yearly_avg,
                       gS.char_stats.total, total_avg)
end

-- 主函数(translator)：处理命令 /tj, /tjs 和 /tje
function M.func(input, seg, env)
    if input == "/tj" then 
        local summary = M.format_speed_summary()
        yield(Candidate("punct", seg.start, seg._end, summary, ""))
    elseif input == "/tjs" then
        local summary = M.format_char_stats_summary()
        yield(Candidate("punct", seg.start, seg._end, summary, ""))
    elseif input == "/tje" then
        -- 手动结束当前会话
        if M.end_session_manually() then
            yield(Candidate("punct", seg.start, seg._end, "会话已手动结束", ""))
        else
            yield(Candidate("punct", seg.start, seg._end, "没有活跃的会话可结束", ""))
        end
    end
end

-- 初始化
function M.init(env)
    -- 确保全局状态已初始化
    if not gS then gS = {} end
    
    -- 加载保存的数据
    M.load_stats()
    
    -- 初始化会话相关状态
    gS.session_start = 0
    gS.last_commit_time = 0
    gS.session_chars = 0
    gS.session_active = false
    gS.show_current_speed = false
    
    -- 确保日期统计是最新的
    M.update_date_stats()
    
    -- 提交回调
    local function commit_fallback(ctx)
        local input_text = ctx.input
        if input_text and (input_text:find("^/tj") or input_text:find("^/tjs") or input_text:find("^/tje")) then
            ctx:clear()
            return
        end
        
        -- 放宽输入条件，不只统计字母输入，且不限制上屏字符数
        if input_text then
            local commit_text = ctx:get_commit_text()
            if commit_text and M.get_commit_length(commit_text) > 0 then
                local input_length = M.get_commit_length(commit_text)
                M.update_stats(input_length)
            end
        end
    end
    
    if not M.init_flag then 
        M.init_flag = true
    end
    
    env.engine.context.commit_notifier:connect(commit_fallback)
    env.engine.context.key_event_notifier:connect(key_event_callback)
end

-- 析构
function M.fini(env)
    -- 保存数据
    M.save_stats(true)
end

return M