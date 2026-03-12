import pandas as pd

# 1. 读取原始 CSV 文件
# 假设列名是 'x', 'y', 'value'
df = pd.read_csv('output_voxel_hard.csv')

# 2. 按 'x' 和 'y' 分组，并将同组的 'value' 相加
# as_index=False 的作用是保持 x, y 作为普通的列，而不是变成行索引
merged_df = df.groupby(['x', 'y'], as_index=False)['r_pn'].sum()

# 3. 查看合并后的结果
print(merged_df.head())

# 4. 保存为新的 CSV 文件
merged_df.to_csv('merged_data.csv', index=False)
print("合并完成！已保存为 merged_data.csv")