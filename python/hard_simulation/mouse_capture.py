from pynput import mouse, keyboard

print("开始录制鼠标操作，按 ESC 结束...")

recording = True

def on_click(x, y, button, pressed):
    if pressed and recording:
        print(f"pyautogui.click({x}, {y})")

def on_press(key):
    global recording
    if key == keyboard.Key.f1:
        recording = False
        print("录制结束")
        return False  # 停止监听

# 同时监听鼠标和键盘
mouse_listener = mouse.Listener(on_click=on_click)
keyboard_listener = keyboard.Listener(on_press=on_press)

mouse_listener.start()
keyboard_listener.start()

keyboard_listener.join()
mouse_listener.stop()
