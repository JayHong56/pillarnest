import numpy as np

def int16_to_hex(v):
    v = np.int16(v)
    return f"{np.uint16(v):04X}"

def int32_to_hex(v):
    v = np.int32(v)
    return f"{np.uint32(v):08X}"


# 读入 48x11 的十进制 txt
W = np.loadtxt("weight_int16.txt", dtype=np.int16)   # shape [48, 11]
assert W.shape == (48, 11)

with open("weight.mem", "w") as f:
    for row in W:
        # 将 row 反转，使得 ic=0 处于字符串末尾（即生成的 Hex 的低位 LSB）
        line = "".join(int16_to_hex(x) for x in reversed(row))
        f.write(line + "\n")

B = np.loadtxt("bias_int32.txt", dtype=np.int32)   # shape [48]
assert B.shape == (48,)

with open("bias.mem", "w") as f:
    for x in B:
        f.write(int32_to_hex(x) + "\n")