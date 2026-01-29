import pandas as pd
import matplotlib.pyplot as plt

# 1. 读取 CSV 文件
# 确保文件路径正确，这里假设文件名为 'hash_data.csv'
try:
    df = pd.read_csv('ssimulation_result.csv')
except FileNotFoundError:
    print("找不到文件，请确保 csv 文件在当前目录下或提供绝对路径")
    exit()

# -------------------------------------------------------
# 核心逻辑：去重
# -------------------------------------------------------
# 需求：对于每一个单独的点(Key_X, Key_Y)，如果落在一个Bucket ID，则高增1
#      若点重复则不再增1。
#
# drop_duplicates 会保留第一次出现的 (Key_X, Key_Y) 组合，
# 删除后续重复的行。这完全符合你的计数要求。
df_unique = df.drop_duplicates(subset=['Key_X', 'Key_Y'])

# -------------------------------------------------------
# 统计与数据补全
# -------------------------------------------------------
# 1. 统计去重后每个 Bucket_ID 出现的次数
counts = df_unique['Bucket_ID'].value_counts()

# 2. 强制补全 0-255 的范围
# 因为可能有些 Bucket 没有点落入，如果不补全，直方图横坐标会缺失
# fill_value=0 表示没有数据的 Bucket 计数为 0
counts_0_to_255 = counts.reindex(range(256), fill_value=0)

# -------------------------------------------------------
# 绘图
# -------------------------------------------------------
plt.figure(figsize=(12, 6))

# 绘制柱状图
# index 是 Bucket_ID (0-255), values 是计数
plt.bar(counts_0_to_255.index, counts_0_to_255.values, 
        width=1.0, color='steelblue', edgecolor='black', linewidth=0.5)

# 设置图表细节
plt.title('Bucket Load Distribution (Unique Points)', fontsize=14)
plt.xlabel('Bucket ID (0-255)', fontsize=12)
plt.ylabel('Count', fontsize=12)
plt.xlim(0, 255)  # 严格限制横坐标显示范围
plt.grid(axis='y', linestyle='--', alpha=0.5)

# 保存图片或显示
plt.savefig('bucket_distribution.png')
plt.show()

# 打印一些统计信息帮助分析
print(f"原始数据条数: {len(df)}")
print(f"去重后数据条数: {len(df_unique)}")
print(f"最大负载: {counts_0_to_255.max()} (at Bucket {counts_0_to_255.idxmax()})")
print(f"空桶数量: {(counts_0_to_255 == 0).sum()}")