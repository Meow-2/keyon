; 窗口相关通用工具。
; 只放跨模块复用的小函数，避免 manager 之间复制同一段基础代码。
class windowHelper {
  ; 把裸 hwnd 转成 AHK WinTitle 可识别的 ahk_id 表达式。
  static toWinId(hwnd) {
    return "ahk_id " hwnd
  }

  ; 给热键名补上 $ 前缀，强制使用键盘 hook 注册。
  ; 已经显式带 $ 的写法保持不变；A & B 这类自定义组合键本身依赖 hook，不能再额外补 $。
  static buildHookHotkeyName(hotkeyName) {
    if (hotkeyName = "" || SubStr(hotkeyName, 1, 1) = "$" || InStr(hotkeyName, " & ")) {
      return hotkeyName
    }

    return "$" hotkeyName
  }

  ; 判断数组中是否已有指定值。
  static arrayHas(values, expectedValue) {
    for value in values {
      if (value = expectedValue) {
        return true
      }
    }

    return false
  }

  ; 给窗口应用 Windows 11 风格外观。
  ; 优先启用 Mica 背景、沉浸式深色模式和圆角；不支持时静默回退。
  static applyMicaWindowStyle(hwnd) {
    trueValue := 1
    roundCornerPreference := 2
    micaBackdropType := 2

    this.trySetDwmWindowAttribute(hwnd, 20, "int", trueValue)
    this.trySetDwmWindowAttribute(hwnd, 19, "int", trueValue)
    this.trySetDwmWindowAttribute(hwnd, 33, "int", roundCornerPreference)
    this.trySetDwmWindowAttribute(hwnd, 38, "int", micaBackdropType)
  }

  ; 给带标题栏的窗口进一步统一边框、标题栏和文字颜色。
  ; 用于需要标准关闭按钮和标题栏的窗口，避免出现默认亮色边框。
  static applyTitledWindowChromeStyle(hwnd) {
    static darkCaptionColor := 0x202020
    static lightTextColor := 0xF5F5F5
    static noBorderColor := 0xFFFFFFFE

    this.trySetDwmWindowAttribute(hwnd, 34, "uint", noBorderColor)
    this.trySetDwmWindowAttribute(hwnd, 35, "uint", darkCaptionColor)
    this.trySetDwmWindowAttribute(hwnd, 36, "uint", lightTextColor)
  }

  ; 包一层 DWM 属性写入，避免低版本系统或不支持的属性直接抛错。
  static trySetDwmWindowAttribute(hwnd, attribute, valueType, value) {
    attributeValue := Buffer(4, 0)
    NumPut(valueType, value, attributeValue)

    try {
      DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", attribute, "ptr", attributeValue, "int", attributeValue.Size)
      return true
    } catch Error {
      return false
    }
  }

  ; 以当前活动窗口所在屏幕为锚点，返回工作区居中位置。
  ; 取不到活动窗口时退回鼠标所在屏幕，保证弹窗仍能出现在合理位置。
  static getCenteredPosition(windowWidth, windowHeight, anchorHwnd := 0) {
    anchorHwnd := anchorHwnd ? anchorHwnd : WinExist("A")
    try {
      WinGetPos(&anchorX, &anchorY, &anchorWidth, &anchorHeight, this.toWinId(anchorHwnd))
      centerX := anchorX + anchorWidth / 2
      centerY := anchorY + anchorHeight / 2
    } catch Error {
      MouseGetPos(&centerX, &centerY)
    }

    monitorIndex := this.getMonitorIndexAt(centerX, centerY)
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)

    return {
      x: Round(left + ((right - left - windowWidth) / 2)),
      y: Round(top + ((bottom - top - windowHeight) / 2))
    }
  }

  ; 根据坐标查找所在显示器。
  ; 找不到时回退到主显示器，保证弹窗一定能定位出来。
  static getMonitorIndexAt(x, y) {
    monitorCount := MonitorGetCount()

    Loop monitorCount {
      MonitorGet(A_Index, &left, &top, &right, &bottom)
      if (x >= left && x < right && y >= top && y < bottom) {
        return A_Index
      }
    }

    return 1
  }
}
