import pyautogui
import time
from pynput import keyboard

pyautogui.FAILSAFE = True  # 鼠标移到左上角强制停止

clicks = [
    (871, 1055),
    (606, 384),
    (872, 1053),
    (746, 385),
    (867, 1052),
    (863, 383),
    (872, 1050),
    (999, 389),
    (867, 1051),
    (1141, 378),
    (867, 1055),
    (597, 517),
    (870, 1053),
    (737, 504),
    (872, 1061),
    (876, 511),
    (869, 1055),
    (1013, 524),
    (870, 1058),
    (1137, 515),
    (870, 1052),
    (602, 650),
    (871, 1049),
    (737, 646),
    (869, 1057),
    (876, 652),
    (869, 1055),
    (1006, 650),
    (871, 1057),
    (1137, 650),
    (870, 1055),
    (615, 783),
    (869, 1049),
    (741, 774),
    (872, 1062),
    (870, 778),
    (871, 1055),
    (1004, 774),
    (873, 1064),
    (1137, 779)
]

running = True

def on_press(key):
    global running
    if key == keyboard.Key.f1:
        print("检测到 F1，正在停止...")
        running = False
        return False

listener = keyboard.Listener(on_press=on_press)
listener.start()

print("3秒后开始执行，按 F1 停止...")
time.sleep(3)

# 只执行一次
for x, y in clicks:
    if not running:
        break
    pyautogui.click(x, y)
    time.sleep(0.2)

print("执行完成，程序结束")
