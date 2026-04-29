import os


# ==========================================
# 1. 硬件位阶与符号扩展工具
# ==========================================
def mask_u(val: int, width: int) -> int:
    """无符号截断，保留低 width 位"""
    return val & ((1 << width) - 1)


def sign_extend(val: int, width: int) -> int:
    """符号位扩展并限制位宽，模拟 FPGA 寄存器的自然溢出与截断"""
    val = mask_u(val, width)
    sign_bit = 1 << (width - 1)
    if val & sign_bit:
        return val - (1 << width)
    return val


# ==========================================
# 2. .mem 文件解析器
# ==========================================
def readmemh_bias(filepath: str, num_elements: int, width: int):
    """解析 Bias 文件，例如 32-bit bias.mem"""
    data = [0] * num_elements

    if filepath == "NOTHING" or not os.path.exists(filepath):
        print(f"⚠️ 警告: 未找到 {filepath}，Bias 默认初始化为 0。")
        return data

    with open(filepath, "r", encoding="utf-8") as f:
        row_idx = 0
        for line in f:
            line = line.split("//")[0].strip().replace("_", "")
            if not line:
                continue

            data[row_idx] = sign_extend(int(line, 16), width)
            row_idx += 1

            if row_idx >= num_elements:
                break

    if row_idx < num_elements:
        print(
            f"⚠️ 警告: Bias 文件行数不足，期望 {num_elements} 行，实际读取 {row_idx} 行。"
        )

    return data


def readmemh_weight(filepath: str, rows: int, cols: int, width: int):
    """
    解析 Weight 文件。

    当前配置:
        OUT_PT_DIM    = 64
        EXPAND_PT_DIM = 9
        WEIGHT_WIDTH  = 16

    所以 weight.mem 期望:
        64 行
        每行 9 * 16 = 144 bit = 36 个 hex 字符

    对齐硬件:
        Verilog 中 weight_row_rom[sel_oc][i_k*WEIGHT_WIDTH+:WEIGHT_WIDTH]
        因此每行 hex 的最右侧 16 bit 对应 k=0，
        再往左依次对应 k=1, k=2, ..., k=8。
    """
    data = [[0] * cols for _ in range(rows)]

    if filepath == "NOTHING" or not os.path.exists(filepath):
        print(f"⚠️ 警告: 未找到 {filepath}，Weight 默认初始化为 0。")
        return data

    chars_per_col = width // 4
    expected_len = cols * chars_per_col

    with open(filepath, "r", encoding="utf-8") as f:
        row_idx = 0
        for line in f:
            line = line.split("//")[0].strip().replace("_", "")
            if not line:
                continue

            # 补齐前导 0，防止高位 0 被文本省略
            line = line.zfill(expected_len)

            # 如果文件每行比期望更长，保留低 expected_len 个 hex 字符，
            # 这与 Verilog 固定位宽寄存器读入时保留低位的行为更接近。
            if len(line) > expected_len:
                line = line[-expected_len:]

            # 从右向左切片，对齐 Verilog 的 [k*16+:16]
            for k in range(cols):
                right_idx = expected_len - k * chars_per_col
                left_idx = right_idx - chars_per_col
                val_hex = line[left_idx:right_idx]
                data[row_idx][k] = sign_extend(int(val_hex, 16), width)

            row_idx += 1

            if row_idx >= rows:
                break

    if row_idx < rows:
        print(f"⚠️ 警告: Weight 文件行数不足，期望 {rows} 行，实际读取 {row_idx} 行。")

    return data


# ==========================================
# 3. PFN 硬件行为级仿真核心
# ==========================================
class PfnLayerBitTrue:
    def __init__(self, weight_file="NOTHING", bias_file="NOTHING"):
        # ------------------------------------------
        # 硬件参数，对齐新版 pfn_layer
        # ------------------------------------------
        self.EXPAND_PT_DIM = 9
        self.OUT_PT_DIM = 64
        self.PT_WIDTH = 16
        self.WEIGHT_WIDTH = 16
        self.ACC_WIDTH = 32

        # ------------------------------------------
        # 载入定点权重与 bias
        # ------------------------------------------
        self.weights = readmemh_weight(
            weight_file,
            self.OUT_PT_DIM,
            self.EXPAND_PT_DIM,
            self.WEIGHT_WIDTH,
        )

        self.biases = readmemh_bias(
            bias_file,
            self.OUT_PT_DIM,
            self.ACC_WIDTH,
        )

        # ------------------------------------------
        # Max Pool 状态
        # ReLU 后结果是非负 bit pattern，这里按 unsigned 保存
        # ------------------------------------------
        self.max_pool_regs = [0] * self.OUT_PT_DIM
        self.pt_cnt = 0

    def float_to_input_fixed(self, pt_data_float: list):
        """
        将 9 维浮点输入转换为 PFN 输入定点格式。

        当前 9 维定义，列号从 0 开始:
            dim 0: x                  Q8.8
            dim 1: y                  Q8.8
            dim 2: z                  Q4.12
            dim 3: intensity          Q1.15
            dim 4: x - mean           Q8.8
            dim 5: y - mean           Q8.8
            dim 6: z - mean           Q4.12
            dim 7: x - vmean          Q8.8
            dim 8: y - vmean          Q8.8

        注意:
            如果你的第 8 维实际是 z - vmean，则应把 dim 8 也按 Q4.12 处理。
        """
        assert (
            len(pt_data_float) == self.EXPAND_PT_DIM
        ), f"输入必须是 {self.EXPAND_PT_DIM} 维，当前是 {len(pt_data_float)} 维"

        q_pt_data = []

        for dim_idx, val in enumerate(pt_data_float):
            if dim_idx == 3:
                # intensity: Q1.15
                fixed_val = int(round(val * 32768.0))
            elif dim_idx == 2 or dim_idx == 6:
                # z, z-mean: Q4.12
                fixed_val = int(round(val * 4096.0))
            else:
                # others: Q8.8
                fixed_val = int(round(val * 256.0))

            q_pt_data.append(sign_extend(fixed_val, self.PT_WIDTH))

        return q_pt_data

    def process_point(
        self, pt_data_float: list, is_last: bool, voxel_x: int = 0, voxel_y: int = 0
    ):
        """
        单点输入，Voxel 结束时输出 64 维 PFN 特征。

        输入:
            pt_data_float: 9 维浮点输入，顺序为 dim0 到 dim8
            is_last:      当前点是否为当前 voxel 的最后一个点
            voxel_x/y:    仅用于输出记录

        输出:
            如果 is_last=False，返回 None。
            如果 is_last=True，返回一个 dict。
        """
        # ---------------------------------------------------------
        # [模拟 PFE] Float -> 输入定点格式
        # ---------------------------------------------------------
        q_pt_data = self.float_to_input_fixed(pt_data_float)

        # 注意:
        # 这里不要 reverse。
        # Verilog 中 s_axis_pfe_data[k*PT_WIDTH+:PT_WIDTH] 对应第 k 维。
        # Python 中 q_pt_data[k] 也应该对应第 k 维。
        self.pt_cnt += 1

        # ---------------------------------------------------------
        # [模拟 PFN] MAC 累加树与 ReLU
        # ---------------------------------------------------------
        for ch in range(self.OUT_PT_DIM):
            # 1. Bias 对齐
            # Verilog: op_bias[i_j] = $signed(bias_rom[sel_oc]) <<< 8;
            bias_val = sign_extend(self.biases[ch], self.ACC_WIDTH)
            mac = sign_extend(bias_val << 8, self.ACC_WIDTH)

            # 2. 9 路乘累加
            for k in range(self.EXPAND_PT_DIM):
                w = sign_extend(self.weights[ch][k], self.WEIGHT_WIDTH)
                d = q_pt_data[k]

                # Verilog st2_mult 是 ACC_WIDTH 位 signed
                mult_res = sign_extend(w * d, self.ACC_WIDTH)

                # Verilog st3_mac_tree 是 ACC_WIDTH 位 signed
                mac = sign_extend(mac + mult_res, self.ACC_WIDTH)

            # 3. 反量化倍数
            # Verilog: dequant_temp[j_2] = st3_mac_tree[j_2] * 994;
            dequant_temp = sign_extend(mac * 779, 64)

            # 4. ReLU 与截断
            # Verilog:
            #   if (st3_mac_tree[j_2] < 0)
            #       relu_comb[j_2] = 0;
            #   else
            #       relu_comb[j_2] = dequant_temp[j_2][PT_WIDTH+20-1 : 20];
            if mac < 0:
                relu_val = 0
            else:
                shifted_val = dequant_temp >> 20
                relu_val = mask_u(shifted_val, self.PT_WIDTH)

            # 5. Max Pool
            # ReLU 后按 unsigned 比较
            if relu_val > self.max_pool_regs[ch]:
                self.max_pool_regs[ch] = relu_val

        # ---------------------------------------------------------
        # [模拟 PFN] Voxel 数据吐出
        # ---------------------------------------------------------
        if is_last:
            out_features = list(self.max_pool_regs)

            result = {
                "voxel_x": voxel_x,
                "voxel_y": voxel_y,
                "pt_cnt": self.pt_cnt,
                "data_q88": out_features,
                # ReLU 输出按 unsigned Q8.8 还原
                "data_float": [val / 256.0 for val in out_features],
            }

            # 清空 Max Pool 状态
            self.max_pool_regs = [0] * self.OUT_PT_DIM
            self.pt_cnt = 0

            return result

        return None


# ==========================================
# 4. 运行剧本
# ==========================================
if __name__ == "__main__":
    print("=" * 60)
    print("🚀 PFN 硬件级 Python 仿真器，新版: Float In -> Q8.8 Out")
    print("   OUT_PT_DIM = 64, EXPAND_PT_DIM = 9")
    print("=" * 60)

    # 1. 实例化仿真模型
    sim = PfnLayerBitTrue(
        weight_file=r"E:\mmdetection3d\my_output_parameters\pfn_layer_fused_int_kitti\mem\pfn_weight.mem",
        bias_file=r"E:\mmdetection3d\my_output_parameters\pfn_layer_fused_int_kitti\mem\bias.mem",
    )

    # 2. 模拟上游传来的点，9维:
    #    x, y, z, intensity, x-mean, y-mean, z-mean, x-vmean, y-vmean
    points_in_voxel = [
[-0.078125,0.039063,-0.246826,0.189972,-0.070313,0.027344,0.195801,-0.078125,0.039063],
[-0.070313,0.062500,-0.919922,0.479980,-0.062500,0.050781,-0.477295,-0.070313,0.062500],
[-0.054688,0.062500,-1.577881,0.239990,-0.046875,0.050781,-1.135254,-0.054688,0.062500],
[-0.042969,0.042969,-0.058838,0.589996,-0.035156,0.031250,0.383789,-0.042969,0.042969],
[-0.039063,0.003906,0.125977,0.279999,-0.031250,-0.007813,0.568604,-0.039063,0.003906],
[-0.023438,0.050781,-0.006836,0.259979,-0.015625,0.039063,0.435791,-0.023438,0.050781],
[-0.007813,0.039063,-0.119873,0.579987,0.000000,0.027344,0.322754,-0.007813,0.039063],
[-0.003906,0.003906,-0.546875,0.439972,0.003906,-0.007813,-0.104248,-0.003906,0.003906],
[-0.003906,0.000000,-0.306885,0.389984,0.003906,-0.011719,0.135742,-0.003906,0.000000],
[0.019531,-0.046875,-0.500000,0.209991,0.027344,-0.058594,-0.057373,0.019531,-0.046875],
[0.042969,0.062500,-0.542969,0.529999,0.050781,0.050781,-0.100342,0.042969,0.062500],
[0.054688,-0.074219,-1.057861,0.269989,0.062500,-0.085938,-0.615234,0.054688,-0.074219],
[0.066406,-0.054688,-0.500977,0.229980,0.074219,-0.066406,-0.058350,0.066406,-0.054688],
[0.066406,-0.007813,0.062988,0.359985,0.074219,-0.019531,0.505615,0.066406,-0.007813]

    ]

    vox_x, vox_y = 0, 188

    # 3. 逐点输入并输出
    print(
        f"📡 送入 Voxel ({vox_x}, {vox_y})，包含 {len(points_in_voxel)} 个浮点坐标点..."
    )

    for i, pt_float in enumerate(points_in_voxel):
        is_last_point = i == len(points_in_voxel) - 1

        out = sim.process_point(
            pt_float,
            is_last=is_last_point,
            voxel_x=vox_x,
            voxel_y=vox_y,
        )

        if out is not None:
            print("\n✅ PFN Layer 运算完毕，触发输出：")
            print(
                f"  📍 坐标: X={out['voxel_x']}, Y={out['voxel_y']} | 总点数: {out['pt_cnt']}"
            )
            print(f"  📊 {sim.OUT_PT_DIM}维特征输出:")

            for c in range(sim.OUT_PT_DIM):
                q_val = out["data_q88"][c]
                f_val = out["data_float"][c]
                print(
                    f"      Ch[{c:02d}]: "
                    f"Q8.8定点值 = {q_val:>5d} "
                    f"(0x{q_val & 0xFFFF:04X})  ->  "
                    f"还原浮点 = {f_val:.6f}"
                )
