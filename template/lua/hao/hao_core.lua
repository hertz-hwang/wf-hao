--[[
Name: hao_core.lua
名称: 好码方案核心函数
Version: 20250716
Author: 荒
Purpose: 好码方案的 RIME lua 提供核心函数

Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International
-------------------------------------
]]
---@diagnostic disable: undefined-global

local core = {
  kRejected = 0,
  kAccepted = 1,
  kNoop = 2,
  kVoid = "kVoid",
  kGuess = "kGuess",
  kSelected = "kSelected",
  kConfirmed = "kConfirmed",
  kNull = "kNull",     -- 空節點
  kScalar = "kScalar", -- 純數據節點
  kList = "kList",     -- 列表節點
  kMap = "kMap",       -- 字典節點
  kShift = 0x1,
  kLock = 0x2,
  kControl = 0x4,
  kAlt = 0x8,
}

--- 取出输入中当前正在翻译的一部分
---@param context Context
function core.current(context)
  local segment = context.composition:toSegmentation():back()
  if not segment then
    return nil
  end
  return context.input:sub(segment.start + 1, segment._end)
end

-- 由translator記録輸入串, 傳遞給filter
core.input_code = ''
-- 由translator計算暫存串, 傳遞給filter
core.stashed_text = ''

-- 開關枚舉
core.switch_names = {
  hao_embeded_cands = "hao_embeded_cands",
  hao_completion    = "hao_completion",
}

-- 從方案配置中讀取字符串
function core.parse_conf_str(env, path, default)
  local str = env.engine.schema.config:get_string(env.name_space .. "/" .. path)
  if not str and default and #default ~= 0 then
      str = default
  end
  return str
end

-- 從方案配置中讀取字符串列表
function core.parse_conf_str_list(env, path, default)
  local list = {}
  local conf_list = env.engine.schema.config:get_list(env.name_space .. "/" .. path)
  if conf_list then
      for i = 0, conf_list.size - 1 do
          table.insert(list, conf_list:get_value_at(i):get_string())
      end
  elseif default then
      list = default
  end
  return list
end

-- 構造開關變更回調函數
---@param option_names table
function core.get_switch_handler(env, option_names)
  env.option = env.option or {}
  local option = env.option
  local name_set = {}
  if option_names then
      for name in pairs(option_names) do
          name_set[name] = true
      end
  end
  -- 返回通知回調, 當改變選項值時更新暫存的值
  ---@param name string
  return function(ctx, name)
      if name_set[name] then
          option[name] = ctx:get_option(name)
          if option[name] == nil then
              -- 當選項不存在時默認爲啟用狀態
              option[name] = true
          end
          -- 刷新, 使 lua 組件讀取最新開關狀態
          ctx:refresh_non_confirmed_composition()
      end
  end
end

---通過 unicode 編碼輸入字符 @lost-melody
function core.unicode()
  local space = utf8.codepoint(" ")
  return function(args)
    local code = tonumber(string.format("0x%s", args[1] or ""))
    return utf8.char(code or space)
  end
end

-- x-release-please-start-version
core.version = "10.1.0"
-- x-release-please-end

---按照优先顺序获取文件：用户目录 > 系统目录
---@param filename string 相对路径
---@retur string | nil
function core.get_filename_with_fallback(filename)
  local _path = filename:gsub("^/+", "") -- 去掉开头的斜杠

  local user_path = rime_api.get_user_data_dir() .. '/' .. _path
  if core.file_exists(user_path) then
      return user_path
  end

  local shared_path = rime_api.get_shared_data_dir() .. '/' .. _path
  if core.file_exists(shared_path) then
      return shared_path
  end

  return nil
end

---判断文件是否存在
function core.file_exists(filename)
  local f = io.open(filename, "r")
  if f ~= nil then
      io.close(f)
      return true
  else
      return false
  end
end

---判断是否在命令模式
---@param context Context | nil
---@return boolean
function core.is_function_mode_active(context)
  if not context or not context.composition or context.composition:empty() then
      return false
  end

  local seg = context.composition:back()
  if not seg then return false end

  return seg:has_tag("number") or  -- number_translator.lua 数字金额转换 R+数字
      seg:has_tag("unicode") or    -- unicode.lua 输出 Unicode 字符 U+小写字母或数字
      --seg:has_tag("punct") or      -- 标点符号 全角半角提示
      seg:has_tag("calculator") or -- super_calculator.lua V键计算器
      seg:has_tag("shijian") or    -- shijian.lua /rq /sr 等与时间日期相关功能
      seg:has_tag("Ndate")         -- shijian.lua N日期功能
end

-- 全局内容
---@alias PROCESS_RESULT ProcessResult
core.RIME_PROCESS_RESULTS = {
  kRejected = 0, -- 表示处理器明确拒绝了这个按键，停止处理链但不返回 true
  kAccepted = 1, -- 表示处理器成功处理了这个按键，停止处理链并返回 true
  kNoop = 2,     -- 表示处理器没有处理这个按键，继续传递给下一个处理器
}

return core