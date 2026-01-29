import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# ==========================================
# 1. 定义 MurmurHash3 哈希函数
# ==========================================
def hash_murmur3(x, y, buckets=64, seed=0):
    """
    实现了 MurmurHash3 (32-bit) 的核心逻辑，专门处理两个整数输入 (x, y)。
    """
    # 32位混合常量
    c1 = 0xcc9e2d51
    c2 = 0x1b873593
    r1 = 15
    r2 = 13
    m = 5
    n = 0xe6546b64

    h1 = seed

    # ----------------------------------------
    # 辅助函数：32位循环左移
    def rotl32(val, r):
        return ((val << r) & 0xFFFFFFFF) | ((val & 0xFFFFFFFF) >> (32 - r))
    
    # 辅助函数：处理一个 4字节块 (block)
    def mix_k1(k):
        k = (k * c1) & 0xFFFFFFFF
        k = rotl32(k, r1)
        k = (k * c2) & 0xFFFFFFFF
        return k

    def mix_h1(h, k):
        h = h ^ k
        h = rotl32(h, r2)
        h = (h * m + n) & 0xFFFFFFFF
        return h
    # ----------------------------------------

    # Body: 将 X 和 Y 视为两个连续的 4字节块进行处理
    # 处理 X
    k1 = int(x) & 0xFFFFFFFF  # 确保是32位整数
    k1 = mix_k1(k1)
    h1 = mix_h1(h1, k1)

    # 处理 Y
    k2 = int(y) & 0xFFFFFFFF
    k2 = mix_k1(k2)
    h1 = mix_h1(h1, k2)

    # Finalization: 假设总长度是 8 字节 (两个 int32)
    length = 8
    h1 = h1 ^ length

    # fmix32: 最终的雪崩混合
    h1 = h1 ^ (h1 >> 16)
    h1 = (h1 * 0x85ebca6b) & 0xFFFFFFFF
    h1 = h1 ^ (h1 >> 13)
    h1 = (h1 * 0xc2b2ae35) & 0xFFFFFFFF
    h1 = h1 ^ (h1 >> 16)

    # 映射到桶
    return h1 % buckets

# ==========================================
# 2. 读取数据 (保持不变)
# ==========================================
try:
    # 你的文件名
    df = pd.read_csv('ssimulation_result.csv')
    # 清理列名空格
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
# 3. 分批处理与循环显示
# ==========================================
BATCH_SIZE = 500
total_rows = len(df)
num_batches = (total_rows + BATCH_SIZE - 1) // BATCH_SIZE

print(f"开始分批显示，每批 {BATCH_SIZE} 个数据，共 {num_batches} 批。")
print("提示：请【关闭当前图表窗口】以查看下一批数据。")

for i in range(num_batches):
    start_idx = i * BATCH_SIZE
    end_idx = min((i + 1) * BATCH_SIZE, total_rows)
    
    current_batch_df = df.iloc[start_idx:end_idx].copy()
    
    # 批次内去重
    df_unique = current_batch_df.drop_duplicates(subset=['Key_X', 'Key_Y']).copy()
    
    if len(df_unique) == 0:
        print(f"Batch {i+1}: 无有效数据 (全部重复)，跳过。")
        continue

    # ==========================================
    # 4. 计算哈希值 (调用新的 MurmurHash3)
    # ==========================================
    df_unique['Calculated_Hash'] = df_unique.apply(
        lambda row: hash_murmur3(row['Key_X'], row['Key_Y']), axis=1
    )

    # 5. 统计分布
    bucket_counts = df_unique['Calculated_Hash'].value_counts().reindex(range(64), fill_value=0)
    
    mean_load = bucket_counts.mean()
    max_load = bucket_counts.max()

    # ==========================================
    # 绘制直方图
    # ==========================================
    plt.figure(figsize=(14, 7))

    # 使用不同颜色区分，暗示这是新的哈希算法
    bars = plt.bar(bucket_counts.index, bucket_counts.values, 
                   width=1.0, color='#d65f5f', edgecolor='black', linewidth=0.3) # 红色系

    plt.axhline(y=mean_load, color='blue', linestyle='--', label=f'Avg Load: {mean_load:.2f}')

    plt.title(f'Batch {i+1}/{num_batches} - MurmurHash3 Collision Histogram', fontsize=16)
    plt.xlabel('Hash Bucket ID (0-63)', fontsize=12)
    plt.ylabel('Number of Points', fontsize=12)
    plt.xlim(0, 64)
    
    plt.grid(axis='y', linestyle='--', alpha=0.5)
    plt.legend()

    print("-" * 30)
    print(f"Batch {i+1} 报告 (MurmurHash3):")
    print(f"  唯一点数: {len(df_unique)}")
    print(f"  最大冲突: {max_load} (Bucket {bucket_counts.idxmax()})")
    print(f"  空桶数量: {(bucket_counts == 0).sum()}")
    
    plt.show() 

print("所有批次显示完毕。")