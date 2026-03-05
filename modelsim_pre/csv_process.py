import pandas as pd
import numpy as np
# # 设置显示的最大行数 (None 表示不限制，显示所有行)
# pd.set_option('display.max_rows', None)

# # 设置显示的最大列数 (None 表示不限制，显示所有列)
# pd.set_option('display.max_columns', None)

# # 如果内容太宽被换行，还可以设置显示宽度
# pd.set_option('display.width', 1000)
# ==========================================
# 1. 配置参数
# ==========================================
CSV_FILE_PATH = "ssimulation_result.csv"  # 你的 CSV 文件路径
INTERVAL_THRESHOLD = 5000                 # 【核心设置】阈值：间隔 > 5000 的会被忽略

# ==========================================
# 2. 读取数据
# ==========================================
try:
    df = pd.read_csv(CSV_FILE_PATH)
    df.columns = df.columns.str.strip() # 清理列名空格
    
    # 确保 Key_X, Key_Y 存在
    if 'Key_X' not in df.columns or 'Key_Y' not in df.columns:
        raise ValueError("CSV 列名错误，必须包含 Key_X 和 Key_Y")
        
except Exception as e:
    print(f"读取文件失败: {e}")
    # (仅演示用) 如果没有文件，生成一个简单的 dummy DataFrame
    print("生成测试数据演示逻辑...")
    df = pd.DataFrame({'Key_X': [10, 10, 10], 'Key_Y': [20, 20, 20]}, index=[0, 100, 6000])
    # 这里 index 100 -> 6000 间隔是 5900，应该被过滤

# ==========================================
# 3. 核心分析逻辑 (带阈值过滤)
# ==========================================
def calculate_filtered_max_interval(group):
    # 获取该体素出现的所有行号 (Index)
    indices = group.index.sort_values().values
    
    if len(indices) < 2:
        return None # 无法计算间隔
    
    # 计算相邻间隔
    intervals = np.diff(indices)
    
    # 【关键步骤】过滤：只保留 <= 阈值的间隔
    # 这样，首尾那种跨度很大的“假邻近”或者中间断档的数据就会被剔除
    valid_intervals = intervals[intervals <= INTERVAL_THRESHOLD]
    
    if len(valid_intervals) == 0:
        return None # 所有间隔都超标，视为无效
        
    return valid_intervals.max()

# ==========================================
# 4. 执行计算并输出
# ==========================================
print(f"正在计算 (忽略 > {INTERVAL_THRESHOLD} 的间隔)...")

# 按体素分组计算
result_series = df.groupby(['Key_X', 'Key_Y']).apply(calculate_filtered_max_interval)

# 格式化结果
result_df = result_series.dropna().to_frame(name='Max_Interval')
result_df = result_df.sort_values('Max_Interval', ascending=False)

print("-" * 50)
print(f"符合条件 (间隔 <= {INTERVAL_THRESHOLD}) 的最大间隔前 5 名:")
print("-" * 50)
print(result_df.head(100))

# 可选：保存到文件
# result_df.to_csv("interval_analysis_result.csv")