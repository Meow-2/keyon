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
  ; 优先用窗口句柄直接取显示器，避免高 DPI 或多屏缩放下用窗口坐标反推显示器产生偏差。
  static getCenteredPosition(windowWidth, windowHeight, anchorHwnd := 0) {
    anchorHwnd := anchorHwnd ? anchorHwnd : WinExist("A")
    workArea := anchorHwnd ? this.getWindowWorkArea(anchorHwnd) : ""

    if !IsObject(workArea) {
      MouseGetPos(&centerX, &centerY)
      workArea := this.getPointWorkArea(centerX, centerY)
    }

    return {
      x: Round(workArea.left + ((workArea.right - workArea.left - windowWidth) / 2)),
      y: Round(workArea.top + ((workArea.bottom - workArea.top - windowHeight) / 2))
    }
  }

  ; 获取窗口所在显示器的工作区。
  ; MonitorFromWindow 不依赖调用方用 GetWindowRect 读取出的坐标，更适合跨 DPI 缩放场景。
  static getWindowWorkArea(hwnd) {
    try {
      monitorHandle := DllCall("user32\MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
    } catch Error {
      return ""
    }

    return this.getMonitorWorkArea(monitorHandle)
  }

  ; 获取指定坐标所在显示器的工作区；主要用于没有可用锚点窗口时的兜底。
  static getPointWorkArea(x, y) {
    monitorIndex := this.getMonitorIndexAt(x, y)
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)

    return {
      left: left,
      top: top,
      right: right,
      bottom: bottom
    }
  }

  ; 读取 Win32 HMONITOR 对应的工作区矩形。
  static getMonitorWorkArea(monitorHandle) {
    if !monitorHandle {
      return ""
    }

    monitorInfo := Buffer(40, 0)
    NumPut("uint", monitorInfo.Size, monitorInfo, 0)

    try {
      if !DllCall("user32\GetMonitorInfoW", "ptr", monitorHandle, "ptr", monitorInfo, "int") {
        return ""
      }
    } catch Error {
      return ""
    }

    return {
      left: NumGet(monitorInfo, 20, "int"),
      top: NumGet(monitorInfo, 24, "int"),
      right: NumGet(monitorInfo, 28, "int"),
      bottom: NumGet(monitorInfo, 32, "int")
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
