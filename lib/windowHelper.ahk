; 窗口相关通用工具。
; 只放跨模块复用的小函数，避免 manager 之间复制同一段基础代码。
class windowHelper {
  ; 把裸 hwnd 转成 AHK WinTitle 可识别的 ahk_id 表达式。
  static toWinId(hwnd) {
    return "ahk_id " hwnd
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
