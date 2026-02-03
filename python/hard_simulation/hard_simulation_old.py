from __future__ import annotations
from dataclasses import dataclass
from typing import List, Optional, Tuple, Dict
import pandas as pd
from collections import deque

# -----------------------------
# 常量：与 Verilog 对齐
# -----------------------------
ST_EMPTY = 0b00
ST_OCCU  = 0b01
ST_TOMB  = 0b10

COORD_WIDTH = 11
VN_WIDTH = 5
TIMER_WIDTH = 16

BUCKETS = 64
SLOTS_PER_BUCKET = 4
ADDR_WIDTH = 8          # 0..255 = {bucket[5:0], slot[1:0]}
TABLE_SIZE = 256
LIFE_CYCLE = 100        # 与参数一致

# -----------------------------
# 工具：截断到固定位宽（模拟硬件寄存器）
# -----------------------------
def mask_u(val: int, width: int) -> int:
    return val & ((1 << width) - 1)

def sign_extend(val: int, width: int) -> int:
    """把 Python int 按 width 当作有符号数解释（模拟 signed [W-1:0]）"""
    val = mask_u(val, width)
    sign = 1 << (width - 1)
    return val - (1 << width) if (val & sign) else val

# -----------------------------
# 哈希函数：输出 bucket_id (0..63)
# 说明：你 RTL 用 hash_func_multiplicative 模块。
# 这里提供一个可替换实现；如果你给出 RTL 具体公式，我可以 1:1 对齐。
# -----------------------------
def hash_bucket_id_rtl(key_x: int, key_y: int) -> int:
    """
    Python 仿真版 hash_func_multiplicative
    与 RTL 位级一致
    """

    COORD_WIDTH = 11
    BUCKET_AW = 6

    PRIME_X = 10368889
    PRIME_Y = 10000169

    # ---------- 1. 模拟 signed [10:0] ----------
    def signed(val, width):
        mask = (1 << width) - 1
        val &= mask
        if val & (1 << (width - 1)):
            val -= (1 << width)
        return val
 
    x = signed(key_x, COORD_WIDTH)
    y = signed(key_y, COORD_WIDTH)

    # ---------- 2. signed 乘法，截断为 36-bit ----------
    mult_x = x * PRIME_X
    mult_y = y * PRIME_Y

    # Verilog: wire signed [35:0]
    mult_x &= (1 << 36) - 1
    mult_y &= (1 << 36) - 1

    # ---------- 3. XOR 混合 ----------
    mixed = mult_x ^ mult_y
    mixed &= (1 << 36) - 1  # 明确 36-bit

    # ---------- 4. 取 mixed[24:19] ----------
    hash_out = (mixed >> 19) & ((1 << BUCKET_AW) - 1)

    return hash_out
# -----------------------------
# 表项结构（对应 ENTRY = {st, kx, ky, pn, ts}）
# -----------------------------
@dataclass
class Entry:
    st: int = ST_EMPTY
    kx: int = 0
    ky: int = 0
    pn: int = 0
    ts: int = 0  # last_access_time / timestamp

    def is_free_or_tomb(self) -> bool:
        return self.st in (ST_EMPTY, ST_TOMB)

    def is_occu_and_match(self, x: int, y: int) -> bool:
        return self.st == ST_OCCU and self.kx == x and self.ky == y


class ExpireManagerRTL:
    """
    软件版 hash_expire_manager：
    - DQ 深度 = LIFE_CYCLE
    - 每次 write_commit 推入 write_addr
    - DQ 满后，每次 commit 弹出一个 cand_addr，做 shadow 读 + expired 判断
    - expired -> 写 TOMB + 产生 expire 事件
    """
    def __init__(self, life_cycle: int):
        self.life_cycle = int(life_cycle)
        self.dq = deque()  # 存放 write_addr，最大长度 = LIFE_CYCLE
        self.expired_events = []  # (kx, ky, addr, pn)

    def on_write_commit(self, time_now: int, write_addr: int, table: list[list[Entry]]):
        """
        对应 RTL 的 write_commit=1 时钟行为（功能级，不做两拍流水延迟）。
        table: table[bucket][slot]
        write_addr: 0..255 ({bucket[5:0], slot[1:0]})
        """
        # push
        if len(self.dq) < self.life_cycle:
            self.dq.append(write_addr)
            return  # DQ 未满，不产生 cand

        # DQ 已满：pop cand，再 push 新的（与环形队列 steady-state 等价）
        cand_addr = self.dq.popleft()
        self.dq.append(write_addr)


        # shadow read（软件直接读当前表项，相当于 rdata_shadow）
        bucket = (cand_addr >> 2) & 0x3F
        slot   = cand_addr & 0x3
        e = table[bucket][slot]

        # expired 判断： (OCCU) && ((time_now - ts) > LIFE_CYCLE)
        dt = (time_now - e.ts) & ((1 << TIMER_WIDTH) - 1)  # 16-bit wrap
        # print(f"ExpireManagerRTL: Check cand_addr={cand_addr} st={e.st} time_now={time_now} entry_ts={e.ts} dt={dt}")
        if e.st == ST_OCCU and dt > self.life_cycle:
            # print(f"ExpireManagerRTL: Expire entry at addr={cand_addr} time_now={time_now} entry_ts={e.ts} dt={dt}")
            # 产生过期事件（对应 fifo_in_data）
            self.expired_events.append((e.kx, e.ky, cand_addr, e.pn))
            # 写 tomb（b_we/b_addr/b_wdata）
            table[bucket][slot] = Entry(st=ST_TOMB, kx=0, ky=0, pn=0, ts=0)

    def pop_events(self):
        ev = self.expired_events[:]
        self.expired_events.clear()
        return ev


# -----------------------------
# 仿真器主体
# -----------------------------
class HashBucketTableSim:
    def __init__(
        self,
        buckets: int = BUCKETS,
        slots_per_bucket: int = SLOTS_PER_BUCKET,
        life_cycle: int = LIFE_CYCLE
    ):
        self.buckets = buckets
        self.slots_per_bucket = slots_per_bucket
        self.life_cycle = life_cycle
        self.expire_mgr = ExpireManagerRTL(LIFE_CYCLE)

        # table[bucket][slot] = Entry
        self.table: List[List[Entry]] = [
            [Entry() for _ in range(slots_per_bucket)]
            for _ in range(buckets)
        ]

        # RTL: global_timer 只在 did_write 时 +1
        self.global_timer: int = 0

        # 记录过期输出（模拟 m_axis_expire_tdata）
        # (kx, ky, out_idx, pn)
        self.expired_events: List[Tuple[int, int, int, int]] = []

    def _pack_out_idx(self, bucket_id: int, slot: int) -> int:
        # out_idx = {bucket[5:0], slot[1:0]}  -> 8-bit
        return ((bucket_id & 0x3F) << 2) | (slot & 0x3)

    def _is_expired(self, e: Entry) -> bool:
        if e.st != ST_OCCU:
            return False
        # 注意：RTL expire_manager 以 global_timer 为 time_now
        return (self.global_timer - e.ts) > self.life_cycle

    def get_bram_loads(self):
        """
        返回 4 块 BRAM 的负载（每块是一个 slot 平面）
        统计口径：ST_OCCU 且未过期
        """
        loads = [0] * self.slots_per_bucket  # 4

        for b in range(self.buckets):
            for s in range(self.slots_per_bucket):
                e = self.table[b][s]
                if e.st == ST_OCCU and (not self._is_expired(e)):
                    loads[s] += 1

        capacity_each = self.buckets  # 每块 BRAM 深度=BUCKETS=64
        pct = [100.0 * x / capacity_each for x in loads]
        return loads, pct
    
    def process(self, key_x: int, key_y: int):
        # 模拟 signed 位宽输入
        x = sign_extend(key_x, COORD_WIDTH)
        y = sign_extend(key_y, COORD_WIDTH)

        start_bucket = hash_bucket_id_rtl(x, y)
        time_now = self.global_timer  # 对齐 RTL：更新前的 global_timer

        busy = True
        found = False
        table_full = False
        out_idx = 0
        out_pn = 0
        did_write = False

        # ---------
        # 线性探测：从 start_bucket 开始，最多探测 BUCKETS 次
        # ---------
        for probe in range(self.buckets):
            bucket_id = (start_bucket + probe) % self.buckets
            slots = self.table[bucket_id]

            hit = False
            hit_way = 0
            free_found = False
            free_way = 0

            # 先在当前 bucket 里扫 4 个 slot
            for i in range(self.slots_per_bucket):
                if (not hit) and slots[i].is_occu_and_match(x, y):
                    hit = True
                    hit_way = i
                if (not free_found) and slots[i].is_free_or_tomb():
                    free_found = True
                    free_way = i

            # 命中：更新 pn
            if hit:
                found = True
                out_idx = self._pack_out_idx(bucket_id, hit_way)
                new_pn = mask_u(slots[hit_way].pn + 1, VN_WIDTH)
                out_pn = new_pn
                slots[hit_way] = Entry(
                    st=ST_OCCU, kx=x, ky=y,
                    pn=new_pn,
                    ts=mask_u(time_now, TIMER_WIDTH)
                )
                did_write = True
                break

            # 未命中但有空位：插入
            if free_found:
                found = True
                out_idx = self._pack_out_idx(bucket_id, free_way)
                out_pn = 1
                slots[free_way] = Entry(
                    st=ST_OCCU, kx=x, ky=y,
                    pn=1,
                    ts=mask_u(time_now, TIMER_WIDTH)
                )
                did_write = True
                break

            # 当前 bucket 满且无命中：继续 probe 下一个 bucket

        
        # probe 一圈还没写入/命中：表满
        if not did_write:
            table_full = True
            print(f"Table FULL at key=({x},{y}) time={time_now}")
            loads, pct = sim.get_bram_loads()
            print(f"pt={i} timer={sim.global_timer} loads={loads} pct={[round(x,1) for x in pct]}")

        # 写提交：驱动 expire manager + timer 自增
        if did_write:
            # print(x, y, out_idx)
            self.expire_mgr.on_write_commit(time_now=time_now, write_addr=out_idx, table=self.table)
            self.global_timer = mask_u(self.global_timer + 1, TIMER_WIDTH)

        return {
            "busy": busy,
            "found": found,
            "out_idx": out_idx,
            "out_point_number": out_pn,
            "table_full": table_full,
            "bucket_id": start_bucket,       # 原始 hash bucket（起点）
            "probe_steps": probe if did_write else self.buckets,  # 线性探测步数
        }


    def dump_bucket(self, bucket_id: int) -> List[Entry]:
        return list(self.table[bucket_id])

    def pop_expired_events(self) -> List[Tuple[int, int, int, int]]:
        """取走并清空过期事件队列（模拟 AXI-stream 消费）"""
        ev = self.expired_events[:]
        self.expired_events.clear()
        return ev

# -----------------------------
# 示例：简单跑几条
# -----------------------------
if __name__ == "__main__":
    import pandas as pd
    REPORT_INTERVAL = 500

    CSV_FILE = "ssimulation_result.csv"   # ← 改成你的 csv 文件名
    sim = HashBucketTableSim()

    df = pd.read_csv(CSV_FILE)
    df.columns = df.columns.str.strip()   # 防止列名有空格

    # 确认列名：需要 Key_X, Key_Y（你之前文件里就是这两个）
    if "Key_X" not in df.columns or "Key_Y" not in df.columns:
        raise ValueError(f"CSV 列名不对：{df.columns.tolist()}，需要 Key_X, Key_Y")

    cnt = 0
    for i, row in enumerate(df.itertuples(index=False), start=1):
        kx = int(getattr(row, "Key_X"))
        ky = int(getattr(row, "Key_Y"))
        sim.process(kx, ky)
        cnt += 1
        # 你想输出什么都行，这里给个对齐 RTL 的关键输出
        # out_idx 对应 {bucket, slot}，out_point_number 对应 pn
        # if r["found"]:
        #     print(f"k=({kx},{ky}) bucket={r['bucket_id']} out_idx={r['out_idx']} pn={r['out_point_number']} full={r['table_full']}")
        
        if i % REPORT_INTERVAL == 0:
            loads, pct = sim.get_bram_loads()
            print(f"pt={i} timer={sim.global_timer} loads={loads} pct={[round(x,1) for x in pct]}")

    print(f"总共处理点数：{cnt}")
# # 如果你还想看过期事件（模拟 m_axis_expire_tdata）
# expired = sim.pop_expired_events()
# print(f"expired_events={len(expired)}")

