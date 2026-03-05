import open3d as o3d
import numpy as np
import matplotlib.pyplot as plt

# 1. 读取数据
data = np.loadtxt('points_float32.txt')
xyz = data[:, 0:3] # 取前三列 (N, 3)

# 2. 创建 Open3D 点云对象
pcd = o3d.geometry.PointCloud()
pcd.points = o3d.utility.Vector3dVector(xyz)

# 3. (可选) 给点上色
# 使用第4列(intensity)来生成颜色
if data.shape[1] > 3:
    intensity = data[:, 3]
    # 归一化强度到 0-1 之间以便映射颜色
    intensity_norm = (intensity - intensity.min()) / (intensity.max() - intensity.min())
    
    # 使用 matplotlib 的颜色映射将数值转为 RGB
    colormap = plt.get_cmap("jet")
    colors = colormap(intensity_norm)[:, :3] # 取 RGB，丢弃 Alpha 通道
    
    pcd.colors = o3d.utility.Vector3dVector(colors)

# 4. 可视化
print("按 'K' 键可以加粗点的大小，按 '-' 键减小点的大小")
o3d.visualization.draw_geometries([pcd], 
                                  window_name="Point Cloud Visualization",
                                  width=800, height=600)