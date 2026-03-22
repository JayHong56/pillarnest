# 比较硬件和软件的哈希输出结果一致性

import pandas as pd
import sys
import io
import os
# 解决输出编码问题
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def load_data_robust(file_path):
    if not os.path.exists(file_path):
        print(f"错误：找不到文件 {file_path}")
        return None
    
    data = []
    # 尝试多种编码方案
    for enc in ['gbk', 'utf-8', 'utf-16']:
        try:
            with open(file_path, 'r', encoding=enc) as f:
                for line in f:
                    clean_line = line.replace(',', ' ').strip()
                    if not clean_line: continue
                    parts = clean_line.split()
                    # 关键：只取前3列，防止列数过多报错
                    if len(parts) >= 3:
                        try:
                            # 兼容 154.0 这种浮点格式
                            data.append([int(float(parts[0])), int(float(parts[1])), int(float(parts[2]))])
                        except ValueError: continue
            break # 成功读取则跳出编码尝试
        except: continue
            
    if not data:
        print(f"错误：无法从 {file_path} 提取有效数据。")
        return None
    return pd.DataFrame(data, columns=['x', 'y', 'val'])

# 假设 load_data_robust 已经定义（见之前的回复）
df1 = load_data_robust('E:\\verilog\\pillarnest\\output_simulation_old.txt')
df2 = load_data_robust('E:\\verilog\\pillarnest\\modelsim_pre\\ssimulation_result.txt')

if df1 is not None and df2 is not None:
    # 核心操作：重置索引并横向合并
    # axis=1 表示左右拼接，不需要找共同的 x,y，只看行号
    df1 = df1.reset_index(drop=True)
    df2 = df2.reset_index(drop=True)
    
    # 将两张表并列排放
    result = pd.concat([df1, df2], axis=1)
    
    # 重新命名列名以区分
    result.columns = ['x1', 'y1', 'val1', 'x2', 'y2', 'val2']

    # 打印表头
    print(f"{'Row':<6} {'(x1,y1)'} {'(x2,y2)'} {'Val1':<8} {'Val2':<8} {'Status'}")
    print("-" * 75)

    diff_count = 0
    # 遍历每一行进行对比
    for idx, row in result.iterrows():
        # 同时检查坐标和数值是否都一致
        coords_match = (row['x1'] == row['x2']) and (row['y1'] == row['y2'])
        val_match = (row['val1'] == row['val2'])
        
        if coords_match and val_match:
            status = "OK"
        elif not coords_match:
            status = f"COORD_ERR({row['x1']},{row['y1']} vs {row['x2']},{row['y2']})"
            diff_count += 1
        else:
            status = f"VAL_ERR({row['val1']-row['val2']})"
            diff_count += 1
            
        # 打印前500行或只打印错误行，避免输出文件过大
        if diff_count < 100 or not val_match or not coords_match:
             print(f"{idx:<6} ({row['x1']},{row['y1']}) ({row['x2']},{row['y2']})    {row['val1']:<8} {row['val2']:<8} {status}")

    print("-" * 75)
    print(f"总行数: {len(result)} | 错误行数: {diff_count}")