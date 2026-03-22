#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re
import os
import argparse
from pathlib import Path
import matplotlib.pyplot as plt


def parse_verilog_value(val_str: str):
    """
    把类似:
        6'h00
        1'b1
        8'd15
        4'b1010
    转成整数
    """
    val_str = val_str.strip()

    # 匹配 Verilog 常量
    m = re.match(r"(\d+)?'([hHbBdD])([0-9a-fA-F_xXzZ]+)", val_str)
    if not m:
        # 兜底：纯数字
        try:
            return int(val_str, 0)
        except Exception:
            return None

    _, base_char, digits = m.groups()
    base_char = base_char.lower()
    digits = digits.replace("_", "")

    # x/z 暂时不做精细处理，统一返回 None
    if any(ch in digits.lower() for ch in ["x", "z"]):
        return None

    if base_char == "h":
        base = 16
    elif base_char == "b":
        base = 2
    elif base_char == "d":
        base = 10
    else:
        return None

    try:
        return int(digits, base)
    except Exception:
        return None


def sanitize_signal_name(signal_name: str):
    """
    把层级路径转成适合文件名的字符串
    """
    s = signal_name.strip().strip("/")
    s = s.replace("/", "__")
    s = s.replace("[", "_").replace("]", "_")
    s = re.sub(r"[^0-9a-zA-Z_\-\.]+", "_", s)
    return s[:200] if len(s) > 200 else s


def parse_list_file(file_path: str):
    """
    解析 .list 文件
    返回:
        {
            signal_name: [(time_ps, value_int), ...],
            ...
        }
    """
    signal_data = {}
    current_signal = None

    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        for raw_line in f:
            line = raw_line.rstrip("\n")

            # 空行跳过
            if not line.strip():
                continue

            # 判断是不是信号名行
            # 你给的格式通常是:
            #      ps   /tb_xxx/...
            # 或者可能有别的单位列头
            if "/" in line and not re.match(r"^\s*\d+", line):
                # 提取最后那个 /path 信号
                parts = line.split()
                sig_candidates = [p for p in parts if p.startswith("/")]
                if sig_candidates:
                    current_signal = sig_candidates[-1]
                    signal_data.setdefault(current_signal, [])
                continue

            # 判断是不是数据行：开头是时间
            if current_signal is not None:
                m = re.match(r"^\s*(\d+)\s+(.+?)\s*$", line)
                if m:
                    t_ps = int(m.group(1))
                    val_str = m.group(2).strip()
                    val = parse_verilog_value(val_str)
                    signal_data[current_signal].append((t_ps, val))

    # 清理空信号
    signal_data = {k: v for k, v in signal_data.items() if v}
    return signal_data


def plot_signal(signal_name, samples, out_dir, time_unit="ps"):
    """
    画单个信号波形
    """
    times = [t for t, _ in samples]
    values = [v if v is not None else 0 for _, v in samples]

    # 单位换算
    if time_unit == "ns":
        x = [t / 1000.0 for t in times]
        xlabel = "Time (ns)"
    elif time_unit == "us":
        x = [t / 1_000_000.0 for t in times]
        xlabel = "Time (us)"
    else:
        x = times
        xlabel = "Time (ps)"

    plt.figure(figsize=(10, 4))
    plt.step(x, values, where="post")
    plt.xlabel(xlabel)
    plt.ylabel("Value")
    plt.title(signal_name)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()

    fname = sanitize_signal_name(signal_name) + ".png"
    out_path = os.path.join(out_dir, fname)
    plt.savefig(out_path, dpi=180)
    plt.close()

    return out_path


def main():
    parser = argparse.ArgumentParser(description="Batch plot waveforms from .list file")
    parser.add_argument("input", help="input .list file path")
    parser.add_argument(
        "-o", "--output-dir",
        default="wave_plots",
        help="output directory, default: wave_plots"
    )
    parser.add_argument(
        "--time-unit",
        choices=["ps", "ns", "us"],
        default="ps",
        help="x axis time unit"
    )
    parser.add_argument(
        "--signals",
        nargs="*",
        default=None,
        help="only plot signals containing these keywords"
    )
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    signal_data = parse_list_file(args.input)
    if not signal_data:
        print("No valid signal data found.")
        return

    selected = {}
    if args.signals:
        for sig, data in signal_data.items():
            if any(key in sig for key in args.signals):
                selected[sig] = data
    else:
        selected = signal_data

    if not selected:
        print("No matching signals found.")
        return

    print(f"Found {len(selected)} signals.")
    for sig, data in selected.items():
        out = plot_signal(sig, data, args.output_dir, args.time_unit)
        print(f"[OK] {sig} -> {out}")


if __name__ == "__main__":
    main()
