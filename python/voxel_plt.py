import pandas as pd
import matplotlib.pyplot as plt

# 读取 CSV
df = pd.read_csv("ssimulation_result.csv")

# 去除重复点
df_unique = df.drop_duplicates(subset=["Key_X", "Key_Y"])

# 提取坐标
x = df_unique["Key_X"]
y = df_unique["Key_Y"]

# 创建画布
plt.figure(figsize=(6, 6))

# 绘制散点
plt.scatter(x, y, s=10)

# 设置坐标范围 0-719
plt.xlim(0, 719)
plt.ylim(0, 719)

# 坐标轴等比例（防止拉伸）
plt.gca().set_aspect("equal", adjustable="box")

# 反转 Y 轴（如果你是图像坐标系，可选）
# plt.gca().invert_yaxis()

# 标签和标题
plt.xlabel("Key_X")
plt.ylabel("Key_Y")
plt.title("2D Point Visualization")

# 显示网格（可选）
plt.grid(True)

# 显示
plt.show()
