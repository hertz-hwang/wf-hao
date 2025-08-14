local hao = require "hao.hao_core"

local space_proc = {}

---@param env Env
function space_proc.init(env)
end

---@param ch string
local function is_punct_char(ch)
  if not ch or utf8.len(ch) ~= 1 then
    return false
  end
  -- 将所有非字母数字与空白字符视为标点
  return rime_api.regex_match(ch, "[^0-9A-Za-z\\s]")
end

--- 检查字符串中是否包含大写字母（任意位置）
---@param str string
local function has_uppercase(str)
  if not str then return false end
  -- 检查整个字符串中任意位置的大写字母
  return string.match(str, "%u") ~= nil
end

--- 检查是否以斜杠开头
---@param str string
local function starts_with_slash(str)
  return str and string.sub(str, 1, 1) == "/"
end

---@param key_event KeyEvent
---@param env Env
function space_proc.func(key_event, env)
  local context = env.engine.context
  -- 忽略修饰/释放键
  if key_event:release() or key_event:alt() or key_event:ctrl() or key_event:caps() then
    return hao.kNoop
  end

  local seg = context.composition:back()
  if not seg then
    return hao.kNoop
  end

  -- 当前输入（preedit 内容对应的编码）
  local input = hao.current(context)
  if not input or input == "" then
    return hao.kNoop
  end

  -- 特殊处理：以斜杠开头的输入不算空码
  if starts_with_slash(input) then
    return hao.kNoop
  end

  -- 检查是否为空码状态（无候选词）
  local isEmptyCode = false
  if not context:has_menu() then
    isEmptyCode = true  -- 候选区无候选
  else
    local first = seg:get_selected_candidate()
    isEmptyCode = first and first.text == input  -- 首选等于输入内容
  end

  if not isEmptyCode then
    return hao.kNoop
  end

  local repr = key_event:repr()
  -- 跳过常见控制键（注意：空格键不再跳过）
  if repr == "BackSpace" or repr == "Escape" or repr == "Return" or repr == "Tab" then
    return hao.kNoop
  end
  
  -- 处理空格键
  if repr == "space" then
    -- 如果输入中包含大写字母（任意位置），则正常提交
    if has_uppercase(input) then
      return hao.kNoop
    end
    
    -- 否则清空预编辑区
    context:clear()
    return hao.kAccepted
  end
  
  -- 处理标点符号
  local incoming = utf8.char(key_event.keycode)
  if not incoming or utf8.len(incoming) ~= 1 or not is_punct_char(incoming) then
    return hao.kNoop
  end

  -- 完全清空预编辑区
  context:clear()
  return hao.kAccepted
end

return space_proc