# 将硬件仿真结果提取成x,y,r_pn的csv文件
import re
import csv
import os

def hw_log_to_csv(input_txt_path, output_csv_path):
    # 检查输入文件是否存在
    if not os.path.exists(input_txt_path):
        print(f"错误: 找不到输入文件 '{input_txt_path}'")
        return

    # 1. 编译正则表达式，精准匹配 r_pn, x, y 后面的数值
    pattern = re.compile(r'r_pn:\s*(\d+),\s*x:\s*(\d+),\s*y:\s*(\d+)')
    
    extracted_data = []

    # 2. 逐行读取 txt 文件并解析
    with open(input_txt_path, 'r', encoding='utf-8') as infile:
        for line in infile:
            match = pattern.search(line)
            if match:
                r_pn = int(match.group(1))
                x = int(match.group(2))
                y = int(match.group(3))
                # 按照要求的列顺序 [x, y, r_pn] 添加到列表
                extracted_data.append([x, y, r_pn])

    if not extracted_data:
        print("未在文件中匹配到有效数据！请确认日志内容格式。")
        return

    # 3. 将提取的数据写入 CSV 文件
    with open(output_csv_path, 'w', newline='', encoding='utf-8') as outfile:
        writer = csv.writer(outfile)
        
        # 写入表头 (列名)
        writer.writerow(['x', 'y', 'r_pn'])
        
        # 批量写入所有数据行
        writer.writerows(extracted_data)

    print(f"处理完成！共提取了 {len(extracted_data)} 条数据。")
    print(f"数据已成功保存至: {output_csv_path}")

# ================= 使用方法 =================
# 1. 将 'hw_log.txt' 替换为你实际的 log 文本文件路径
# 2. 将 'output_data.csv' 替换为你想要的输出文件名
input_file = r'E:\verilog\pillarnest\modelsim_pre\ssimulation_result_killed.csv'   
output_file = 'output_voxel_hard.csv'

hw_log_to_csv(input_file, output_file)