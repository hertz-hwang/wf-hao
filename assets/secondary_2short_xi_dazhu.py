import sys

def process_line(line):
    line = line.strip()
    if not line:
        return []
    parts = line.split('\t')
    if len(parts) < 2:
        return []
    left_str = parts[0]
    code = parts[1]
    sub_parts = left_str.split(';')
    if len(sub_parts) < 2:
        return []
    right_str = sub_parts[1].strip()
    components = right_str.split()
    output_lines = []
    for comp in components:
        if comp[0].isdigit():
            suffix = comp[0]
            hanzi = comp[1:]
        else:
            suffix = ';'
            hanzi = comp
        output_lines.append(code + suffix + '\t' + hanzi)
    return output_lines

def main(input_file, output_file):
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    output_lines = []
    for line in lines:
        output_lines.extend(process_line(line))
    
    # 使用追加模式('a')而不是写入模式('w')打开文件
    with open(output_file, 'a', encoding='utf-8') as f:
        for out_line in output_lines:
            f.write(out_line + '\n')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python convert.py input.txt output.txt")
        sys.exit(1)
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    main(input_file, output_file)