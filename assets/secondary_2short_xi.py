#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
from pathlib import Path

# ==================== 配置 ====================
# 设为 True → 在对应汉字的**前一行**插入二简二重码
# 设为 False → 在对应汉字的**后一行**插入二简二重码
INSERT_BEFORE = True

# 输入/输出路径（相对或绝对均可）
SRC_FILE   = Path("../schemas/hao/hao/dazhu-xi52.txt")
OUT_FIX    = Path("../schemas/hao/hao/dazhu-xi52-fix.txt")
OUT_TABLE  = Path("../schemas/hao/淅码五二顶二简二重表.txt")
# =============================================

# ---------- 1. 生成所有两位前缀 ----------
prefixes = [a + b for a in "abcdefghijklmnopqrstuvwxyz" for b in "abcdefghijklmnopqrstuvwxyz"]
prefix_map = {p: [] for p in prefixes}  # 存储每个前缀的所有匹配项
char_first_occurrence = {}  # 记录每个汉字首次出现的编码

# ---------- 2. 读取原始码表，收集所有匹配项 ----------
with SRC_FILE.open("r", encoding="utf-8") as f:
    line_number = 0
    for line in f:
        line = line.rstrip()  # 保留行尾空白
        if not line.strip():
            continue
            
        parts = line.split("\t")
        if len(parts) < 2:
            continue
            
        code, char = parts[0].lower(), parts[1]
        
        # 记录汉字首次出现的编码
        if char not in char_first_occurrence:
            char_first_occurrence[char] = (code, line_number)
        
        # 收集所有匹配前缀的条目
        if len(code) >= 2:
            p = code[:2]
            if p in prefix_map:
                prefix_map[p].append((code, char, line_number))
        
        line_number += 1

# ---------- 3. 生成二简码表 ----------
secondary_results = {}  # 存储二重码结果 {prefix: char}
primary_results = {}   # 存储一重码结果 {prefix: char}

with OUT_TABLE.open("w", encoding="utf-8") as out_f:
    for p in prefixes:
        entries = prefix_map[p]
        if not entries:
            out_f.write(f"{p}\t\n")
            out_f.write(f"{p};\t\n")
            continue
        
        # 创建去重字典 {char: (code, line_number)}
        char_map = {}
        for code, char, ln in entries:
            # 只保留每个字符的首次出现
            if char not in char_map:
                char_map[char] = (code, ln)
        
        # 按出现顺序排序字符
        sorted_chars = sorted(char_map.keys(), key=lambda c: char_map[c][1])
        
        # 寻找一重码（恰好两位编码的字符）
        primary_char = None
        for char in sorted_chars:
            code, _ = char_map[char]
            if len(code) == 2:
                primary_char = char
                break
        
        # 寻找二重码（第一个非一重码字符）
        secondary_char = None
        for char in sorted_chars:
            if char != primary_char:
                secondary_char = char
                break
        
        # 写入一重码
        if primary_char:
            out_f.write(f"{p}\t{primary_char}\n")
            primary_results[p] = primary_char
        else:
            out_f.write(f"{p}\t\n")
        
        # 写入二重码
        if secondary_char:
            out_f.write(f"{p};\t{secondary_char}\n")
            secondary_results[p] = secondary_char
        else:
            out_f.write(f"{p};\t\n")

# ---------- 4. 修正原始码表 ----------
# 读取原始文件内容
with SRC_FILE.open("r", encoding="utf-8") as f:
    original_lines = f.readlines()

# 创建处理后的行列表
fixed_lines = []
handled_chars = set()  # 记录已处理的二重码字符

# 处理每一行
line_index = 0
while line_index < len(original_lines):
    line = original_lines[line_index].rstrip("\n")
    stripped = line.strip()
    
    # 跳过空行
    if not stripped:
        fixed_lines.append(line)
        line_index += 1
        continue
        
    parts = stripped.split("\t")
    if len(parts) < 2:
        fixed_lines.append(line)
        line_index += 1
        continue
        
    code, char = parts[0], parts[1]
    
    # 检查是否为二重码字符的首次出现
    if char in secondary_results.values():
        # 获取首次出现信息
        first_code, first_line = char_first_occurrence[char]
        
        # 当前行是首次出现行
        if line_index == first_line:
            # 找到对应的前缀
            for p, c in secondary_results.items():
                if c == char:
                    new_entry = f"{p};\t{char}"
                    
                    if INSERT_BEFORE:
                        # 在前一行插入
                        fixed_lines.append(new_entry)
                        fixed_lines.append(line)
                    else:
                        # 在后一行插入
                        fixed_lines.append(line)
                        fixed_lines.append(new_entry)
                    
                    handled_chars.add(char)
                    break
            line_index += 1
            continue
    
    # 普通行直接添加
    fixed_lines.append(line)
    line_index += 1

# 处理未在原始码表中出现的二重码字符
for p, char in secondary_results.items():
    if char not in handled_chars:
        new_entry = f"{p};\t{char}"
        fixed_lines.append(new_entry)

# ---------- 5. 写回修正后的码表 ----------
with OUT_FIX.open("w", encoding="utf-8") as out_f:
    for line in fixed_lines:
        out_f.write(line + "\n")

# ---------- 6. 完成提示 ----------
print("处理完成！")
print(f"二简一重和二简二重表已写入: {OUT_TABLE}")
print(f"修正后的码表已写入: {OUT_FIX}")
print(f"当前模式：{'在前一行插入' if INSERT_BEFORE else '在后一行插入'}")