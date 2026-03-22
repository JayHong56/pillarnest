import re
import csv

input_file = "output_simulation_old.txt"
output_file = "output_voxel_simulation.csv"

pattern = re.compile(r"Point=\((\d+),\s*(\d+)\).*?PN=(\d+)")

rows = []

encodings = ["utf-8", "utf-8-sig", "gbk", "gb2312", "latin1"]
content = None

for enc in encodings:
    try:
        with open(input_file, "r", encoding=enc) as f:
            content = f.readlines()
        print(f"成功使用编码: {enc}")
        break
    except UnicodeDecodeError:
        continue

if content is None:
    raise ValueError("无法识别文件编码，请手动检查文件编码。")

for line in content:
    match = pattern.search(line)
    if match:
        x = int(match.group(1))
        y = int(match.group(2))
        pn = int(match.group(3))
        rows.append([x, y, pn])

with open(output_file, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.writer(f)
    writer.writerow(["x", "y", "value"])
    writer.writerows(rows)

print(f"提取完成，共 {len(rows)} 条，已保存到 {output_file}")
