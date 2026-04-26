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
}
