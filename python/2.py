import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# ==========================================
# 1. 定义乘法哈希函数 (保持不变)
# ==========================================
def hash_multiplicative(x, y, buckets=64):
    PRIME_X = 10368889 
    PRIME_Y = 10000169 
    
    val_x = x * PRIME_X
    val_y = y * PRIME_Y
    
    mixed_val = val_x ^ val_y
    
    # 右移 10 位取低 8 位，再取模 buckets
    hash_idx = (mixed_val >> 10) & 0xFF
    return hash_idx % buckets

# ==========================================
# 2. 读取数据 (保持不变)
# ==========================================
try:
    # 你的文件名
    df = pd.read_csv('ssimulation_result.csv')
    df.columns = df.columns.str.strip()
    print("数据读取成功，共 {} 行".format(len(df)))

except FileNotFoundError:
    print("未找到文件，生成模拟数据...")
    # 模拟 12606 个数据
    df = pd.DataFrame({
        'Key_X': np.random.randint(0, 720, 12606),
        'Key_Y': np.random.randint(0, 720, 12606)
    })

# ==========================================
# 3. 分批处理与循环显示 (核心修改部分)
# ==========================================
BATCH_SIZE = 500
total_rows = len(df)
# 计算总批次数
num_batches = (total_rows + BATCH_SIZE - 1) // BATCH_SIZE

print(f"开始分批显示，每批 {BATCH_SIZE} 个数据，共 {num_batches} 批。")
print("提示：请【关闭当前图表窗口】以查看下一批数据。")

for i in range(num_batches):
    # 1. 确定切片范围
    start_idx = i * BATCH_SIZE
    end_idx = min((i + 1) * BATCH_SIZE, total_rows)
    
    # 2. 获取当前批次的数据
    current_batch_df = df.iloc[start_idx:end_idx].copy()
    
    # 3. 批次内去重
    # 注意：这里是在当前1000个数据内部去重。如果你想看累积去重效果，逻辑会有所不同。
    df_unique = current_batch_df.drop_duplicates(subset=['Key_X', 'Key_Y']).copy()
    
    # 如果这一批数据全是重复的（去重后为空），则跳过或处理
    if len(df_unique) == 0:
        print(f"Batch {i+1}: 无有效数据 (全部重复)，跳过。")
        continue

    # 4. 计算哈希值
    df_unique['Calculated_Hash'] = df_unique.apply(
        lambda row: hash_multiplicative(int(row['Key_X']), int(row['Key_Y'])), axis=1
    )

    # 5. 统计分布
    bucket_counts = df_unique['Calculated_Hash'].value_counts().reindex(range(64), fill_value=0)
    
    # 统计指标
    mean_load = bucket_counts.mean()
    max_load = bucket_counts.max()

    # ==========================================
    # 绘制当前批次的直方图
    # ==========================================
    plt.figure(figsize=(14, 7)) # 每次创建一个新画布

    bars = plt.bar(bucket_counts.index, bucket_counts.values, 
                   width=1.0, color='#4c72b0', edgecolor='black', linewidth=0.3)

    plt.axhline(y=mean_load, color='r', linestyle='--', label=f'Avg Load: {mean_load:.2f}')

    # 动态标题，显示当前批次信息
    plt.title(f'Batch {i+1}/{num_batches} (Rows {start_idx}-{end_idx}) - Hash Collision Histogram', fontsize=16)
    plt.xlabel('Hash Bucket ID (0-63)', fontsize=12)
    plt.ylabel('Number of Points', fontsize=12)
    plt.xlim(0, 64)
    
    # 动态调整 Y 轴范围，防止某一批次突刺看不清，或者固定范围以便对比
    # 这里选择自动适应，也可以固定 plt.ylim(0, 50)
    plt.grid(axis='y', linestyle='--', alpha=0.5)
    plt.legend()

    # 打印当前批次报告
    print("-" * 30)
    print(f"Batch {i+1} 报告 (行 {start_idx} ~ {end_idx}):")
    print(f"  原始数量: {len(current_batch_df)}")
    print(f"  唯一点数: {len(df_unique)}")
    print(f"  最大冲突: {max_load} (Bucket {bucket_counts.idxmax()})")
    print(f"  空桶数量: {(bucket_counts == 0).sum()}")
    
    # 显示图像 (阻塞模式：代码会停在这里直到你关闭窗口)
    plt.show() 

print("所有批次显示完毕。")