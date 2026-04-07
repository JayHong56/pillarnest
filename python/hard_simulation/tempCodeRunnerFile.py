import numpy as np

def evaluate_pseudo_image(sw_pseudo_img: np.ndarray, hw_pseudo_img: np.ndarray):
    """
    评估软硬件伪图 (Pseudo-image) 误差
    参数:
        sw_pseudo_img: 软件计算的伪图 (FP32)，通常 shape 为 [C, H, W]
        hw_pseudo_img: 硬件计算的伪图 (还原为浮点数)，通常 shape 为 [C, H, W]
    """
    # 1. 检查 Shape 是否一致
    assert sw_pseudo_img.shape == hw_pseudo_img.shape, \
        f"❌ Shape 不一致! SW: {sw_pseudo_img.shape}, HW: {hw_pseudo_img.shape}"
    
    print("="*60)
    print("🎯 Pseudo-image 软硬一致性对齐报告")
    print("="*60)

    # ---------------------------------------------------------
    # 指标 5: 空间掩码对齐度 (Mask IoU)
    # 找出通道维度 (C) 上非零的像素点 (H, W 投影)
    # ---------------------------------------------------------
    sw_mask = np.max(np.abs(sw_pseudo_img), axis=0) > 1e-5
    hw_mask = np.max(np.abs(hw_pseudo_img), axis=0) > 1e-5
    
    intersection = np.logical_and(sw_mask, hw_mask).sum()
    union = np.logical_or(sw_mask, hw_mask).sum()
    iou = intersection / union if union > 0 else 1.0
    
    print(f"📍 空间投影 IoU (Mask IoU) : {iou:.6f} ", end="")
    if iou == 1.0:
        print("✅ (体素坐标散射完全正确)")
    else:
        print("❌ (警告：坐标计算有错位或丢失！)")
        
    # ---------------------------------------------------------
    # 过滤背景：我们只在有特征的地方计算数值误差，防止被大量的 0 稀释
    # ---------------------------------------------------------
    valid_mask = np.logical_or(sw_mask, hw_mask)
    # 将 [C, H, W] 按照 valid_mask 提取成 [C, N] 形状，N 为有效 Pillar 数
    sw_valid_features = sw_pseudo_img[:, valid_mask] 
    hw_valid_features = hw_pseudo_img[:, valid_mask]

    if sw_valid_features.size == 0:
        print("\n⚠️ 警告：两张伪图都是全 0，无可对比特征！")
        return

    # ---------------------------------------------------------
    # 指标 1: 余弦相似度 (Cosine Similarity)
    # ---------------------------------------------------------
    # 计算每个 Pillar 特征向量的余弦相似度，然后求平均
    dot_product = np.sum(sw_valid_features * hw_valid_features, axis=0)
    norm_sw = np.linalg.norm(sw_valid_features, axis=0)
    norm_hw = np.linalg.norm(hw_valid_features, axis=0)
    
    # 防止除以 0
    valid_norms = (norm_sw > 0) & (norm_hw > 0)
    cos_sims = dot_product[valid_norms] / (norm_sw[valid_norms] * norm_hw[valid_norms])
    mean_cos_sim = np.mean(cos_sims) if len(cos_sims) > 0 else 0.0
    
    print(f"📐 余弦相似度 (Cos Sim)    : {mean_cos_sim:.6f}")

    # ---------------------------------------------------------
    # 指标 2 & 3: Max Error, MAE, MSE
    # ---------------------------------------------------------
    diff = sw_valid_features - hw_valid_features
    max_err = np.max(np.abs(diff))
    mae = np.mean(np.abs(diff))
    mse = np.mean(diff ** 2)
    
    print(f"💥 最大绝对误差 (Max Err)  : {max_err:.6f}")
    print(f"📉 平均绝对误差 (MAE)      : {mae:.6f}")
    print(f"📉 均方误差 (MSE)          : {mse:.6f}")

    # ---------------------------------------------------------
    # 指标 4: 信号量化噪声比 (SQNR)
    # ---------------------------------------------------------
    signal_power = np.mean(sw_valid_features ** 2)
    noise_power = mse
    if noise_power > 1e-12:
        sqnr = 10 * np.log10(signal_power / noise_power)
    else:
        sqnr = float('inf') # 噪声极小，接近完美
        
    print(f"📡 信号量化噪声比 (SQNR)   : {sqnr:.2f} dB")
    
    print("="*60)
    # 给出诊断建议
    if mean_cos_sim > 0.99 and iou == 1.0:
        print("🎉 诊断结果: 底层模块与软件金标准完美对齐，准备接入 2D CNN Backbone！")
    elif iou < 1.0:
        print("🚨 诊断结果: Scatter 过程出现坐标映射错误，请检查 X/Y 坐标的索引生成逻辑。")
    elif max_err > 1.0:
        print("🚨 诊断结果: 发现极大的数值刺突！可能存在定点数溢出 (Overflow) 或截断错误。")
    else:
        print("💡 诊断结果: 存在一定量化损耗，但无致命错误，可继续评估整体 mAP 表现。")
    print("="*60)


import numpy as np
import os

def parse_txt_to_pseudo_image(filepath: str, grid_h: int = 720, grid_w: int = 720, channels: int = 48) -> np.ndarray:
    """
    将包含 voxel_x, voxel_y 和特征的文本文件，解析并散射为密集的 2D 伪图。
    
    参数:
        filepath: 文本文件路径 (.txt 或 .csv)
        grid_h: 伪图的高度 (对应 Y 轴)，默认 720
        grid_w: 伪图的宽度 (对应 X 轴)，默认 720
        channels: 特征维度，默认 48
        
    返回:
        pseudo_image: 形状为 (channels, grid_h, grid_w) 的 NumPy 数组 (FP32)
    """
    # 1. 初始化全零的密集伪图，形状为 [C, H, W]
    pseudo_image = np.zeros((channels, grid_h, grid_w), dtype=np.float32)

    if not os.path.exists(filepath):
        print(f"⚠️ 错误: 找不到文件 {filepath}")
        return pseudo_image

    valid_count = 0
    drop_count = 0

    print(f"⏳ 正在解析并散射 {filepath} 到 [{channels}, {grid_h}, {grid_w}] 的伪图...")

    with open(filepath, 'r') as f:
        for line_idx, line in enumerate(f):
            line = line.strip()
            
            # 跳过空行或表头 (如果第一行包含英文字母如 "time" 或 "x")
            if not line or line[0].isalpha():
                continue

            # 统一分隔符：将逗号替换为空格，然后按空格切分，兼容 csv 和纯 txt
            parts = line.replace(',', ' ').split()

            # 过滤掉不完整的数据行
            if len(parts) < channels + 2:
                continue

            # ---------------------------------------------------------
            # 🌟 智能提取逻辑：
            # 无论前面有多少个辅助列 (如 time, pt_cnt)，特征永远在最后 48 列
            # ---------------------------------------------------------
            features = np.array(parts[-channels:], dtype=np.float32)

            # 提取坐标：
            # 如果是纯净版 (x, y, 48维) -> 长度为 50 -> x 是索引 0，y 是索引 1
            # 如果是之前 Verilog 生成的 (time, x, y, pt_cnt, 48维) -> 长度为 52 -> x 是 1，y 是 2
            if len(parts) == 50:
                voxel_x = int(float(parts[0]))
                voxel_y = int(float(parts[1]))
            elif len(parts) >= 52:
                voxel_x = int(float(parts[1]))
                voxel_y = int(float(parts[2]))
            else:
                voxel_x = int(float(parts[0]))
                voxel_y = int(float(parts[1]))

            # ---------------------------------------------------------
            # 🌟 坐标散射 (Scatter) 到 2D 伪图
            # 在 [C, H, W] 格式中：H 代表 Y 轴，W 代表 X 轴
            # ---------------------------------------------------------
            if 0 <= voxel_x < grid_w and 0 <= voxel_y < grid_h:
                pseudo_image[:, voxel_y, voxel_x] = features
                valid_count += 1
            else:
                # 记录超出 [0, 719] 边界的废弃体素
                drop_count += 1

    print(f"✅ 散射完成！成功填充了 {valid_count} 个 Pillar，有 {drop_count} 个越界被丢弃。")
    return pseudo_image


import numpy as np
import pandas as pd
import os
def parse_csv_to_pseudo_image(csv_path: str, grid_h: int = 720, grid_w: int = 720, channels: int = 48, max_by_dim: int = 0) -> np.ndarray:
    """
    读取带有表头的 CSV 文件，将其中的 Pillar 特征散射到 (C, H, W) 的伪图中。
    
    参数:
        csv_path: CSV 文件路径
        grid_h: 伪图的高度 (对应 Y 轴)，默认 720
        grid_w: 伪图的宽度 (对应 X 轴)，默认 720
        channels: 特征维度，默认 48
        max_by_dim: 当出现坐标冲突时，以哪个维度的值最大作为保留依据 (默认 0 代表 dim0)
    """
    # 1. 初始化全零的密集伪图，形状为 [C, H, W]
    pseudo_image = np.zeros((channels, grid_h, grid_w), dtype=np.float32)

    if not os.path.exists(csv_path):
        print(f"⚠️ 错误: 找不到文件 {csv_path}")
        return pseudo_image

    print(f"⏳ 正在使用 Pandas 读取 {csv_path} ...")
    
    # 2. 读取 CSV 文件
    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        print(f"⚠️ 读取 CSV 失败: {e}")
        return pseudo_image

    # 检查必需的列是否存在
    if 'voxel_x' not in df.columns or 'voxel_y' not in df.columns:
        print("⚠️ 错误: CSV 中找不到 'voxel_x' 或 'voxel_y' 列！")
        return pseudo_image

    total_voxels = len(df)
    
    # 3. 过滤掉越界的坐标 (保护 NumPy 数组不越界报错)
    df_valid = df[
        (df['voxel_x'] >= 0) & (df['voxel_x'] < grid_w) &
        (df['voxel_y'] >= 0) & (df['voxel_y'] < grid_h)
    ].copy() # 使用 copy 避免 SettingWithCopyWarning
    
    # =========================================================================
    # 🌟 新增逻辑：处理相同体素的重复输出
    # 如果有相同的 (voxel_x, voxel_y)，保留特征 dim{max_by_dim} 最大的一行
    # =========================================================================
    # 判断是否存在重复的坐标
    if df_valid.duplicated(subset=['voxel_x', 'voxel_y']).any():
        target_col = f'dim{max_by_dim}'
        if target_col not in df_valid.columns:
            print(f"⚠️ 警告: 找不到指定的比较列 {target_col}，回退到保留最后一条结果。")
            df_valid = df_valid.drop_duplicates(subset=['voxel_x', 'voxel_y'], keep='last')
        else:
            dup_count_before = len(df_valid)
            # 核心操作：先按目标维度降序排列，然后 drop_duplicates 默认保留第一项（即最大项）
            df_valid = df_valid.sort_values(by=target_col, ascending=False)
            df_valid = df_valid.drop_duplicates(subset=['voxel_x', 'voxel_y'], keep='first')
            
            dup_count_after = len(df_valid)
            print(f"🔄 冲突解决: 发现同一坐标有多个输出结果！已根据 `{target_col}` 的最大值保留，剔除了 {dup_count_before - dup_count_after} 条冗余数据。")
    # =========================================================================

    valid_count = len(df_valid)
    drop_count = total_voxels - valid_count

    if valid_count == 0:
        print("⚠️ 警告: CSV 中没有任何合法的体素坐标！")
        return pseudo_image

    # 4. 提取坐标和特征
    x_coords = df_valid['voxel_x'].astype(int).values
    y_coords = df_valid['voxel_y'].astype(int).values

    feature_cols = [f'dim{i}' for i in range(channels)]
    
    missing_cols = [col for col in feature_cols if col not in df_valid.columns]
    if missing_cols:
        print(f"⚠️ 错误: CSV 中缺失以下特征列: {missing_cols[:5]} ...")
        return pseudo_image

    features = df_valid[feature_cols].values.astype(np.float32)

    # 5. 极速向量化散射
    pseudo_image[:, y_coords, x_coords] = features.T

    print(f"✅ 硬件伪图生成完毕！最终映射了 {valid_count} 个独立 Pillar (共丢弃/过滤 {drop_count} 个点)。")
    return pseudo_image


import numpy as np

def find_max_error_coordinates(sw_pseudo_img: np.ndarray, hw_pseudo_img: np.ndarray, top_k: int = 5):
    """
    找出软硬件伪图误差最大的 Top-K 个坐标点，并打印详细对比。
    伪图形状假定为 [C, H, W]，其中 H 对应 Y，W 对应 X。
    """
    assert sw_pseudo_img.shape == hw_pseudo_img.shape, "Shape 必须一致"
    
    # 1. 计算绝对误差矩阵
    abs_diff = np.abs(sw_pseudo_img - hw_pseudo_img)
    
    # 2. 将 3D 误差矩阵展平，找出最大的 Top-K 个索引
    # np.argsort 会从小到大排序，[::-1] 翻转为从大到小，取前 top_k 个
    flat_indices = np.argsort(abs_diff.flatten())[::-1][:top_k]
    
    print("\n" + "="*60)
    print(f"🚨 误差最大的前 {top_k} 个坐标点分析报告 (Top-{top_k} Errors)")
    print("="*60)
    
    for rank, flat_idx in enumerate(flat_indices):
        # 3. 将一维扁平索引还原回 3D 坐标 (Channel, Y, X)
        c, y, x = np.unravel_index(flat_idx, abs_diff.shape)
        
        err_val = abs_diff[c, y, x]
        sw_val = sw_pseudo_img[c, y, x]
        hw_val = hw_pseudo_img[c, y, x]
        
        # 为了方便看定点数溢出，顺便打印硬件值对应的 Q8.8 整数
        hw_q88 = int(hw_val * 256.0)
        
        print(f"[{rank+1}] 📍 坐标: (X={x}, Y={y}) | 通道: Ch[{c:02d}]")
        print(f"    -> 软件金标准 (SW) : {sw_val:10.5f}")
        print(f"    -> 硬件计算值 (HW) : {hw_val:10.5f}  (底层Q8.8定点整数: {hw_q88} / 16进制: 0x{hw_q88&0xFFFF:04X})")
        print(f"    -> 绝对误差 (Diff) : {err_val:10.5f}")
        print("-" * 50)
        
        # 提前结束条件：如果后面的误差都很小了，就没必要看了
        if err_val < 0.5 and rank > 0:
            print("💡 后续误差已小于 0.5，属于正常量化波动，停止打印。")
            break
# ==========================================
# 调用方法示例：
# ==========================================
# 假设你已经通过之前写的 parse_csv_to_pseudo_image 拿到了 sw_pseudo_img 和 hw_pseudo_img
# find_max_error_coordinates(sw_pseudo_img, hw_pseudo_img, top_k=5)

# ==================== 测试示例 ====================
if __name__ == "__main__":

    hw_file = r"E:\verilog\pillarnest\modelsim_pre\pfn_layer_out.csv"  # 替换成你真实的硬件 txt/csv 路径
    sw_file = r"E:\mmdetection3d\bev_48d_nonzero.txt" # 替换成你真实的软件 txt/csv 路径

    # 2. 解析软件伪图 (如果有的话)

    print("\n--- 读取软件特征 ---")
    sw_fake = parse_txt_to_pseudo_image(sw_file, grid_h=720, grid_w=720, channels=48)

    hw_fake = parse_csv_to_pseudo_image(hw_file, grid_h=720, grid_w=720, channels=48)


    # # 模拟 [通道数=64, 高=400, 宽=400] 的伪图
    # shape = (64, 400, 400)
    
    # # 生成全 0 背景
    # sw_fake = np.zeros(shape, dtype=np.float32)
    # hw_fake = np.zeros(shape, dtype=np.float32)
    
    # # 随机在几个位置放上 Pillar 特征
    # sw_fake[:, 10, 20] = np.random.randn(64)
    # sw_fake[:, 50, 100] = np.random.randn(64)
    
    # # 硬件伪图加入轻微的量化噪声 (模拟 Q8.8 或 INT16)
    # hw_fake[:, 10, 20] = sw_fake[:, 10, 20] + np.random.randn(64) * 0.05
    # hw_fake[:, 50, 100] = sw_fake[:, 50, 100] + np.random.randn(64) * 0.05
    
    # 运行评估
    evaluate_pseudo_image(sw_fake, hw_fake)


    find_max_error_coordinates(sw_fake, hw_fake, top_k=50)