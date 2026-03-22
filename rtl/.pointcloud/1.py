import pandas as pd

# 读取数据文件
# sep='\s+' 表示以任意数量的空格或制表符作为分隔符
# header=None 表示数据没有表头（列名）
df = pd.read_csv('points_float32.txt', sep='\s+', header=None)

# 提取第四列 (索引为 3)
col_4 = df[3]

# 1. 计算最大值
max_val = col_4.max()

# 2. 判断是否有负值 (检查是否任意一个数小于0)
has_negative = (col_4 < 0).any()

# 3. 判断是否全是整数 (检查数字本身和它的整数部分是否相等)
are_all_integers = (col_4 % 1 == 0).all()

# 输出结果
print(f"第四列的最大值是: {max_val}")
print(f"是否有负值: {'是' if has_negative else '否'}")
print(f"是否都是整数: {'是' if are_all_integers else '否'}")