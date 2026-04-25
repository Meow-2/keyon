; 工具类快捷键管理器。
; 当前只负责“查看当前窗口信息和输入法状态”，后续可继续承载其他诊断类快捷键。
class infoManager {
  ; 保存配置路径，并接收 imeManager 实例以复用输入法状态读取逻辑。
  __New(configPath, inputMethodManager) {
    this.configPath := configPath
    this.inputMethodManager := inputMethodManager
    this.config := configReader(configPath)
    this.enabled := this.config.readBool("windowInfo", "enabled", false)
    this.hotkey := this.config.readText("windowInfo", "hotkey")
    this.copyToClipboard := this.config.readBool("windowInfo", "copyToClipboard", true)
  }

  ; 注册信息查看快捷键。
  ; 没有配置 hotkey 或 enabled=false 时直接返回 0，不影响主脚本运行。
  registerHotkeys() {
    if (!this.enabled || this.hotkey = "") {
      return 0
    }

    try {
      Hotkey(this.hotkey, ObjBindMethod(this, "showCurrentInfo"), "On")
      return 1
    } catch Error as err {
      MsgBox("信息查看快捷键注册失败：`n" err.Message, "mine-key")
      return 0
    }
  }

  ; 快捷键触发入口。
  ; 先采集完整信息用于展示；自动复制时复制 apps.ini 最常用的三行推荐配置。
  showCurrentInfo(*) {
    currentInfo := this.buildCurrentInfo()

    if this.copyToClipboard {
      A_Clipboard := currentInfo.clipboardText
    }

    this.showInfoWindow(currentInfo.displayText)
  }

  ; 显示可选中复制的信息窗口。
  ; 上方只读区域展示诊断信息；下方输入框默认聚焦，用于实时观察输入法状态变化。
  showInfoWindow(staticInfoText) {
    initialText := this.buildDisplayText(staticInfoText, 0)
    windowSize := this.measureInfoWindow(initialText)
    infoGui := Gui("-Resize", "mine-key 当前信息")
    infoGui.MarginX := 12
    infoGui.MarginY := 12
    infoGui.SetFont("s9", "Microsoft YaHei UI")
    displayEdit := infoGui.Add("Edit", "ReadOnly Multi WantTab -Wrap -VScroll -HScroll x12 y12 w" windowSize.editWidth " h" windowSize.displayHeight, initialText)
    inputEdit := infoGui.Add("Edit", "x12 y" windowSize.inputY " w" windowSize.editWidth " h" windowSize.inputHeight, "")

    updateInfo := (*) => this.refreshDisplayText(displayEdit, staticInfoText, inputEdit.Hwnd)

    closeInfoWindow(*) {
      SetTimer(updateInfo, 0)
      infoGui.Destroy()
    }

    infoGui.OnEvent("Escape", closeInfoWindow)
    infoGui.OnEvent("Close", closeInfoWindow)
    displayEdit.OnEvent("Focus", (*) => DllCall("HideCaret", "ptr", displayEdit.Hwnd))

    infoGui.Show("w" windowSize.windowWidth " h" windowSize.windowHeight)
    ; 避免窗口打开时默认全选文本；用户需要时仍可手动选择复制。
    SendMessage(0xB1, 0, 0, displayEdit.Hwnd)
    ; 上方只读 Edit 获得焦点后仍会显示闪烁光标；隐藏它更接近普通系统信息弹窗。
    DllCall("HideCaret", "ptr", displayEdit.Hwnd)
    inputEdit.Focus()
    updateInfo()
    SetTimer(updateInfo, 200)
  }

  ; 根据文本行数估算窗口大小。
  ; AHK 的 Edit 控件没有简单的“按换行后实际高度自适应”接口，因此用保守字符宽度估算换行行数。
  measureInfoWindow(infoText) {
    MonitorGetWorkArea(, &left, &top, &right, &bottom)
    workWidth := right - left
    workHeight := bottom - top
    editWidth := Min(720, Max(520, workWidth - 120))
    maxCharsPerLine := Max(40, Floor(editWidth / 7))
    visualLineCount := 0

    for line in StrSplit(infoText, "`n", "`r") {
      lineLength := StrLen(line)
      visualLineCount += Max(1, Ceil(lineLength / maxCharsPerLine))
    }

    inputHeight := 28
    controlGap := 8
    displayHeight := visualLineCount * 19 + 14
    displayHeight := Min(Max(displayHeight, 220), workHeight - inputHeight - controlGap - 80)

    return {
      editWidth: editWidth,
      displayHeight: displayHeight,
      inputHeight: inputHeight,
      inputY: displayHeight + controlGap + 12,
      windowWidth: editWidth + 24,
      windowHeight: displayHeight + inputHeight + controlGap + 24
    }
  }

  ; 汇总当前窗口和输入法信息。
  ; 一次采集同时生成弹窗显示文本和剪贴板文本，避免两次读取活动窗口导致内容不一致。
  buildCurrentInfo() {
    activeHwnd := WinExist("A")
    if !activeHwnd {
      return {
        displayText: "当前没有可识别的活动窗口。",
        clipboardText: ""
      }
    }

    winId := this.toWinId(activeHwnd)
    title := this.getWindowTitle(winId)
    className := this.getWindowClass(winId)
    processName := this.getWindowProcessName(winId)
    pid := this.getWindowPid(winId)
    processPath := this.getWindowProcessPath(winId)
    positionText := this.getWindowPositionText(winId)
    minMaxText := this.getWindowMinMaxText(winId)

    text := ""
    text .= "窗口信息`n"
    text .= "标题: " title "`n"
    text .= "进程名: " processName "`n"
    text .= "进程 ID: " pid "`n"
    text .= "窗口类名: " className "`n"
    text .= "窗口句柄: " activeHwnd "`n"
    text .= "窗口状态: " minMaxText "`n"
    text .= "窗口位置: " positionText "`n"
    text .= "进程路径: " processPath "`n`n"

    targetRecommendation := this.getTargetRecommendation(processPath, processName)

    text .= "可用于 apps.ini 的推荐配置`n"
    text .= "winTitle=ahk_exe " processName "`n"
    text .= "target=" targetRecommendation "`n"
    text .= "processName=" processName "`n`n"

    text .= "可用于 apps.ini 的备用 winTitle 写法`n"
    text .= "winTitle=ahk_class " className "`n"
    text .= "winTitle=ahk_id " activeHwnd "`n"
    text .= "`n"

    if this.copyToClipboard {
      text .= "已复制 winTitle、target、processName 推荐配置到剪贴板。"
    }

    clipboardText := ""
    if (processName != "") {
      clipboardText .= "winTitle=ahk_exe " processName "`n"
      clipboardText .= "target=" targetRecommendation "`n"
      clipboardText .= "processName=" processName
    }

    return {
      displayText: text,
      clipboardText: clipboardText
    }
  }

  ; 拼接静态窗口信息和动态输入法信息。
  ; 输入法信息使用下方输入框的句柄读取，因此用户切换输入法时上方状态可以同步变化。
  buildDisplayText(staticInfoText, inputHwnd) {
    return staticInfoText "`n`n" this.buildInputMethodText(inputHwnd)
  }

  ; 刷新上方只读区域。
  ; 只有文本发生变化时才写回控件，减少闪烁并尽量不打断用户选择文本。
  refreshDisplayText(displayEdit, staticInfoText, inputHwnd) {
    nextText := this.buildDisplayText(staticInfoText, inputHwnd)
    if (displayEdit.Value = nextText) {
      return
    }

    displayEdit.Value := nextText
    SendMessage(0xB1, 0, 0, displayEdit.Hwnd)
    DllCall("HideCaret", "ptr", displayEdit.Hwnd)
  }

  ; 生成实时输入法状态文本。
  ; inputHwnd 为空时退回当前焦点窗口，主要用于窗口创建前的初始尺寸估算。
  buildInputMethodText(inputHwnd) {
    focusedHwnd := inputHwnd ? inputHwnd : this.inputMethodManager.getFocusedWindow()
    focusedWinId := focusedHwnd ? this.toWinId(focusedHwnd) : ""
    inputState := focusedHwnd ? this.inputMethodManager.getInputState(focusedHwnd) : "EN"
    openStatus := focusedHwnd ? this.inputMethodManager.getOpenStatus(focusedHwnd) : 0
    conversionMode := focusedHwnd ? this.inputMethodManager.getConversionMode(focusedHwnd) : 0
    keyboardLayout := focusedHwnd ? this.getKeyboardLayoutText(focusedHwnd) : ""

    text := ""
    text .= "输入法信息（下方输入框，实时刷新）`n"
    text .= "输入焦点句柄: " focusedHwnd "`n"
    text .= "输入焦点表达式: " focusedWinId "`n"
    text .= "输入法状态: " inputState "`n"
    text .= "打开状态码: " openStatus "`n"
    text .= "转换码: " conversionMode "`n"
    text .= "键盘布局: " keyboardLayout
    return text
  }

  ; 生成 target 推荐值。
  ; 完整路径更适合启动指定应用；如果 Windows 拒绝读取进程路径，则退回到进程名。
  getTargetRecommendation(processPath, processName) {
    if (processPath != "") {
      return processPath
    }

    return processName
  }

  ; 获取窗口标题；失败时返回空字符串，避免诊断弹窗本身报错。
  getWindowTitle(winId) {
    try {
      return WinGetTitle(winId)
    } catch Error {
      return ""
    }
  }

  ; 获取窗口类名；常用于构造 ahk_class 匹配规则。
  getWindowClass(winId) {
    try {
      return WinGetClass(winId)
    } catch Error {
      return ""
    }
  }

  ; 获取进程名；常用于构造最稳定的 ahk_exe 匹配规则。
  getWindowProcessName(winId) {
    try {
      return WinGetProcessName(winId)
    } catch Error {
      return ""
    }
  }

  ; 获取进程 ID。
  ; 主要用于临时排查，不建议写入长期配置，因为每次启动都会变化。
  getWindowPid(winId) {
    try {
      return WinGetPID(winId)
    } catch Error {
      return ""
    }
  }

  ; 获取进程完整路径。
  ; 用于确认 target 应该写哪个 exe 或快捷方式。
  getWindowProcessPath(winId) {
    try {
      return WinGetProcessPath(winId)
    } catch Error {
      return ""
    }
  }

  ; 获取窗口位置和尺寸。
  ; 用于排查窗口是否在屏幕外，或后续扩展窗口布局功能。
  getWindowPositionText(winId) {
    try {
      WinGetPos(&x, &y, &w, &h, winId)
      return "x=" x ", y=" y ", w=" w ", h=" h
    } catch Error {
      return ""
    }
  }

  ; 获取窗口最大化/最小化状态。
  ; AHK 中 WinGetMinMax 返回 -1=最小化，0=普通，1=最大化。
  getWindowMinMaxText(winId) {
    try {
      state := WinGetMinMax(winId)
    } catch Error {
      return "未知"
    }

    switch state {
      case -1:
        return "最小化"
      case 1:
        return "最大化"
      default:
        return "普通"
    }
  }

  ; 获取输入焦点线程的键盘布局。
  ; 该值可用于排查当前实际激活的是哪个输入法或键盘布局。
  getKeyboardLayoutText(hwnd) {
    try {
      threadId := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
      keyboardLayout := DllCall("GetKeyboardLayout", "uint", threadId, "ptr")
      return Format("0x{:X}", keyboardLayout)
    } catch Error {
      return ""
    }
  }

  ; 把裸 hwnd 转成 AHK WinTitle 可识别的 ahk_id 表达式。
  toWinId(hwnd) {
    return "ahk_id " hwnd
  }
}
