-- 固顶过滤器
-- 本过滤器读取用户自定义的固顶短语，将其与当前翻译结果进行匹配，如果匹配成功，则将特定字词固顶到特定位置

local hao = require "hao.hao_core"

local this = {}

---@class HaoFixedFilterEnv: Env
---@field fixed { string : string[] }
---@field fixed_lookup { string : { [string]: boolean } } -- 快速查找表
---@field fixed_lengths { string : number[] } -- 预计算的长度表

---@param env HaoFixedFilterEnv
function this.init(env)
    ---@type { string : string[] }
    env.fixed = {}
    ---@type { string : { [string]: boolean } }
    env.fixed_lookup = {}
    ---@type { string : number[] }
    env.fixed_lengths = {}
    
    local path = rime_api.get_user_data_dir() .. ("/%s.fixed.txt"):format(env.engine.schema.schema_id)
    local file = io.open(path, "r")
    if not file then
        return
    end
    
    -- 使用pcall安全读取文件
    local ok, err = pcall(function()
        for line in file:lines() do
            ---@type string, string
            local code, content = line:match("([^\t]+)\t([^\t]+)")
            if not content or not code then
                goto continue
            end
            
            local words = {}
            local lookup = {}
            local lengths = {}
            
            for word in content:gmatch("[^%s]+") do
                table.insert(words, word)
                lookup[word] = true
                table.insert(lengths, utf8.len(word))
            end
            
            env.fixed[code] = words
            env.fixed_lookup[code] = lookup
            env.fixed_lengths[code] = lengths
            ::continue::
        end
    end)
    
    file:close()
    
    if not ok then
        log.error("Error reading fixed phrases: " .. tostring(err))
    end
end

---@param segment Segment
---@param env Env
function this.tags_match(segment, env)
    return segment:has_tag("abc")
end

---@param fixed_phrases string[]
---@param fixed_lengths number[]
---@param unknown_candidates Candidate[]
---@param i number
---@param segment Segment
---@param context Context
function this.finalize(fixed_phrases, fixed_lengths, unknown_candidates, i, segment, context)
    -- 输出设为固顶但是没在候选中找到的候选
    while fixed_phrases[i] do
        local simple_candidate = Candidate("fixed", segment.start, segment._end, fixed_phrases[i], "")
        simple_candidate.preedit = hao.current(context) or ""
        i = i + 1
        yield(simple_candidate)
    end
    
    -- 输出没有固顶的候选
    for _, unknown_candidate in ipairs(unknown_candidates) do
        yield(unknown_candidate)
    end
end

---@param translation Translation
---@param env HaoFixedFilterEnv
function this.func(translation, env)
    local context = env.engine.context
    local composition = context.composition
    if not composition then
        for candidate in translation:iter() do
            yield(candidate)
        end
        return
    end
    
    -- 取出输入中当前正在翻译的一部分
    local segment = composition:toSegmentation():back()
    local input = hao.current(context)
    if not segment or not input then
        for candidate in translation:iter() do
            yield(candidate)
        end
        return
    end
    
    local shape_input = context:get_property("shape_input")
    if shape_input then
        input = input .. shape_input
    end
    
    local fixed_phrases = env.fixed[input]
    if not fixed_phrases then
        for candidate in translation:iter() do
            yield(candidate)
        end
        return
    end
    
    local fixed_lookup = env.fixed_lookup[input]
    local fixed_lengths = env.fixed_lengths[input]
    
    -- 生成固顶候选
    ---@type Candidate[]
    local unknown_candidates = {}
    ---@type { [string]: Candidate }
    local known_candidates = {}
    local i = 1
    local total_candidates = 0
    local max_candidates = env.engine.schema.config:get_int("fixed_filter/max_candidates") or 100
    local finalized = false
    
    for candidate in translation:iter() do
        total_candidates = total_candidates + 1
        if total_candidates > max_candidates then
            if not finalized then
                this.finalize(fixed_phrases, fixed_lengths, unknown_candidates, i, segment, context)
                finalized = true
            end
            yield(candidate)
            goto continue
        end
        
        local text = candidate.text
        
        -- 使用快速查找表检查是否为固顶词
        if fixed_lookup[text] then
            known_candidates[text] = candidate
        else
            table.insert(unknown_candidates, candidate)
        end
        
        -- 每看过一个新的候选之后，看看是否找到了新的固顶候选，如果找到了，就输出
        local current = fixed_phrases[i]
        if current and known_candidates[current] then
            local cand = known_candidates[current]
            cand.type = "fixed"
            yield(cand)
            i = i + 1
        elseif current and fixed_lengths and fixed_lengths[i] > utf8.len(text) then
            -- 使用预计算的长度进行比较
            local simple_candidate = Candidate("fixed", segment.start, segment._end, current, "")
            simple_candidate.preedit = hao.current(context) or ""
            yield(simple_candidate)
            i = i + 1
        end
        ::continue::
    end
    
    if not finalized then
        this.finalize(fixed_phrases, fixed_lengths, unknown_candidates, i, segment, context)
    end
end

return this