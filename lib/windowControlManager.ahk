; 通用窗口管理快捷键。
; 负责关闭当前窗口，以及在当前桌面可管理窗口之间向前/向后切换。
class windowControlManager {
  __New(configPath) {
    this.configPath := configPath
    this.config := configReader(configPath)
    this.enabled := this.config.readBool("windowControl", "enabled", false)
    this.closeHotkey := this.config.readText("windowControl", "closeHotkey")
    this.nextHotkey := this.config.readText("windowControl", "nextHotkey")
    this.previousHotkey := this.config.readText("windowControl", "previousHotkey")
    this.switchMode := this.normalizeSwitchMode(this.config.readText("windowControl", "switchMode", "managed"))
    this.waitSeconds := this.config.readNumber("windowControl", "waitSeconds", 1)
    this.previewSeconds := this.config.readNumber("windowControl", "previewSeconds", 0.6)
    this.previewMaxItems := this.config.readNumber("windowControl", "previewMaxItems", 8)
    this.previewFontSize := this.config.readNumber("windowControl", "previewFontSize", 16)
    this.previewWidth := this.config.readNumber("windowControl", "previewWidth", 760)
    this.windowCycleHwnds := []
    this.previewGui := ""
    this.hidePreviewCallback := ObjBindMethod(this, "hideWindowPreview")
    this.systemSwitchActive := false
    this.systemNextKey := this.buildSystemCycleKey(this.nextHotkey)
    this.systemPreviousKey := this.buildSystemCycleKey(this.previousHotkey)
    this.systemNextCallback := ObjBindMethod(this, "continueSystemWindowSwitch", 1)
    this.systemPreviousCallback := ObjBindMethod(this, "continueSystemWindowSwitch", -1)
    this.finishSystemSwitchCallback := ObjBindMethod(this, "finishSystemWindowSwitchWhenWinReleased")
  }

  ; 注册启用的窗口管理快捷键。
  ; 单个快捷键为空时跳过，避免未配置字段影响其他工具快捷键。
  registerHotkeys() {
    if !this.enabled {
      return 0
    }

    registeredCount := 0
    registeredCount += this.registerHotkey(this.closeHotkey, ObjBindMethod(this, "closeActiveWindow"), "关闭窗口")
    registeredCount += this.registerHotkey(this.nextHotkey, ObjBindMethod(this, "activateAdjacentWindow", 1), "切换到下一个窗口")
    registeredCount += this.registerHotkey(this.previousHotkey, ObjBindMethod(this, "activateAdjacentWindow", -1), "切换到上一个窗口")
    return registeredCount
  }

  ; 注册单个热键，失败时只提示当前热键，不中断脚本。
  registerHotkey(hotkeyName, callback, actionName) {
    if (hotkeyName = "") {
      return 0
    }

    try {
      Hotkey(hotkeyName, callback, "On")
      return 1
    } catch Error as err {
      MsgBox("窗口管理快捷键注册失败：" actionName "`n" err.Message, "mine-key")
      return 0
    }
  }

  ; 关闭当前活动窗口。
  ; 跳过桌面、任务栏、空标题窗口等系统容器，避免误关不可交互窗口。
  closeActiveWindow(*) {
    activeHwnd := WinExist("A")
    if !activeHwnd || !this.isSwitchableWindow(activeHwnd) {
      return false
    }

    try {
      WinClose(this.toWinId(activeHwnd))
      return true
    } catch Error {
      return false
    }
  }

  ; 按窗口 Z 序切换到相邻窗口。
  ; direction=1 表示下一个，direction=-1 表示上一个。
  activateAdjacentWindow(direction, *) {
    if (this.switchMode = "system") {
      return this.sendSystemWindowSwitch(direction)
    }

    hwnds := this.getWindowCycle()
    if (hwnds.Length = 0) {
      return false
    }

    activeHwnd := WinExist("A")
    activeIndex := 0
    for index, hwnd in hwnds {
      if (hwnd = activeHwnd) {
        activeIndex := index
        break
      }
    }

    targetIndex := 1
    if (activeIndex > 0) {
      targetIndex := activeIndex + direction
      if (targetIndex < 1) {
        targetIndex := hwnds.Length
      } else if (targetIndex > hwnds.Length) {
        targetIndex := 1
      }
    }

    this.showWindowPreview(hwnds, targetIndex)
    return this.focusWindow(hwnds[targetIndex])
  }

  ; 使用系统 Alt+Tab 行为切换窗口。
  ; 如果用户仍按住 Win，则保持 Alt 不放，让 Win+J/K 像 Alt+Tab 一样连续循环。
  sendSystemWindowSwitch(direction) {
    this.hideWindowPreview()

    if this.isWinPhysicallyDown() {
      return this.sendWinHeldSystemWindowSwitch(direction)
    }

    return this.sendSingleSystemWindowSwitch(direction)
  }

  ; 发送一次完整的系统窗口切换。
  ; 用于非 Win 触发的 system 模式，行为等同一次 Alt+Tab 或 Alt+Shift+Tab。
  sendSingleSystemWindowSwitch(direction) {
    this.releaseWinForSystemSwitch()

    if (direction > 0) {
      Send("!{Tab}")
    } else {
      Send("!+{Tab}")
    }

    return true
  }

  ; 在用户按住 Win 时维持系统 Alt+Tab 切换会话。
  ; 第一次触发时按下 Alt；后续 J/K 只继续发送 Tab 或 Shift+Tab。
  sendWinHeldSystemWindowSwitch(direction) {
    this.releaseWinForSystemSwitch()

    if !this.systemSwitchActive {
      Send("{Alt down}")
      this.systemSwitchActive := true
      this.enableSystemCycleHotkeys()
      SetTimer(this.finishSystemSwitchCallback, 20)
    }

    this.sendSystemTab(direction)

    return true
  }

  ; 临时释放逻辑 Win 键，避免后续发送的 Alt+Tab 被组合成 Win+Alt+Tab。
  ; 释放前先发送 vkE8 屏蔽键，防止物理 Win 松开时被 Windows 当作单按 Win 并弹出开始菜单。
  releaseWinForSystemSwitch() {
    if this.isWinPhysicallyDown() {
      Send("{Blind}{vkE8}")
    }

    Send("{LWin up}{RWin up}")
    Sleep(10)
  }

  ; system 模式切换会话中的后续 J/K 入口。
  ; 第一次触发后逻辑 Win 已被释放，所以必须临时接管裸触发键继续发送 Tab。
  continueSystemWindowSwitch(direction, *) {
    if (!this.systemSwitchActive || !this.isWinPhysicallyDown()) {
      this.finishSystemWindowSwitchWhenWinReleased()
      return false
    }

    this.sendSystemTab(direction)
    return true
  }

  ; 向系统 Alt+Tab 界面发送一次前进或后退。
  sendSystemTab(direction) {
    if (direction > 0) {
      Send("{Tab}")
    } else {
      Send("{Shift down}{Tab}{Shift up}")
    }
  }

  ; 松开物理 Win 后释放 Alt，让 Windows 确认当前 Alt+Tab 选择。
  finishSystemWindowSwitchWhenWinReleased() {
    if this.isWinPhysicallyDown() {
      return
    }

    SetTimer(this.finishSystemSwitchCallback, 0)

    if this.systemSwitchActive {
      Send("{Alt up}")
      this.systemSwitchActive := false
      this.disableSystemCycleHotkeys()
    }
  }

  ; 启用 system 切换会话内的裸按键接管。
  ; 只在 Alt+Tab 界面打开期间启用，避免平时拦截用户正常输入 J/K。
  enableSystemCycleHotkeys() {
    this.setSystemCycleHotkey(this.systemNextKey, this.systemNextCallback, "On")
    this.setSystemCycleHotkey(this.systemPreviousKey, this.systemPreviousCallback, "On")
  }

  ; 关闭 system 切换会话内的裸按键接管。
  disableSystemCycleHotkeys() {
    this.setSystemCycleHotkey(this.systemNextKey, this.systemNextCallback, "Off")
    this.setSystemCycleHotkey(this.systemPreviousKey, this.systemPreviousCallback, "Off")
  }

  ; 动态启停临时热键。
  ; 热键注册失败不应影响主窗口切换，最坏情况只是连续 J/K 不生效。
  setSystemCycleHotkey(hotkeyName, callback, state) {
    if (hotkeyName = "") {
      return
    }

    try {
      Hotkey(hotkeyName, callback, state)
    } catch Error {
    }
  }

  ; 从 Win 组合快捷键中提取会话内需要接管的实际按键。
  ; 例如 #j 提取为 *j；星号前缀表示忽略其他修饰键状态。
  buildSystemCycleKey(hotkeyName) {
    hotkeyName := Trim(hotkeyName)
    if (hotkeyName = "") {
      return ""
    }

    if InStr(hotkeyName, " & ") {
      parts := StrSplit(hotkeyName, " & ")
      return "*" Trim(parts[parts.Length])
    }

    while (hotkeyName != "" && InStr("*~$<>#!^+", SubStr(hotkeyName, 1, 1))) {
      hotkeyName := SubStr(hotkeyName, 2)
    }

    if (hotkeyName = "") {
      return ""
    }

    return "*" hotkeyName
  }

  ; 检测物理 Win 键是否仍被按住。
  ; 使用物理状态而不是逻辑状态，因为切换时会临时发送 Win up 避免组合成 Win+Alt+Tab。
  isWinPhysicallyDown() {
    return GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
  }

  ; 获取稳定的窗口切换序列。
  ; 直接使用 WinGetList 的实时 Z 序会在每次激活后重排，导致连续切换只在最近两个窗口间跳动。
  getWindowCycle() {
    currentHwnds := this.getSwitchableWindows()
    cycleHwnds := []

    for hwnd in this.windowCycleHwnds {
      if this.arrayHas(currentHwnds, hwnd) {
        cycleHwnds.Push(hwnd)
      }
    }

    for hwnd in currentHwnds {
      if !this.arrayHas(cycleHwnds, hwnd) {
        cycleHwnds.Push(hwnd)
      }
    }

    this.windowCycleHwnds := cycleHwnds
    return cycleHwnds
  }

  ; 获取当前可切换的普通窗口列表。
  ; WinGetList 返回的是 Z 序窗口；过滤后用于实现 Win+J/Win+K 的前后切换。
  getSwitchableWindows() {
    hwnds := []

    for hwnd in WinGetList() {
      if this.isSwitchableWindow(hwnd) {
        hwnds.Push(hwnd)
      }
    }

    return hwnds
  }

  ; 判断数组中是否已有指定窗口句柄。
  arrayHas(values, expectedValue) {
    for value in values {
      if (value = expectedValue) {
        return true
      }
    }

    return false
  }

  ; 统一窗口切换模式写法。
  ; managed 使用本项目自己的窗口列表和预览；system 直接交给 Windows Alt+Tab。
  normalizeSwitchMode(switchMode) {
    switchMode := StrLower(Trim(switchMode))

    switch switchMode {
      case "system", "altTab", "alttab", "windows":
        return "system"
      default:
        return "managed"
    }
  }

  ; 显示本次窗口切换的候选列表。
  ; 使用居中的轻量 GUI 作为预览，箭头标记即将切换到的目标窗口。
  showWindowPreview(hwnds, targetIndex) {
    if (this.previewSeconds <= 0) {
      return
    }

    this.hideWindowPreview()

    previewGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border")
    previewGui.BackColor := "FFFFFF"
    previewGui.MarginX := 24
    previewGui.MarginY := 18
    previewGui.SetFont("s" this.previewFontSize, "Microsoft YaHei UI")
    previewGui.Add("Text", "w" this.previewWidth, "窗口切换")

    maxItems := Min(this.previewMaxItems, hwnds.Length)
    prefixWidth := 32
    labelWidth := this.previewWidth - prefixWidth - 8

    Loop maxItems {
      index := A_Index
      hwnd := hwnds[index]
      lineText := index ". " this.getWindowLabel(hwnd)
      prefixText := index = targetIndex ? "▶" : ""

      if (index = targetIndex) {
        previewGui.SetFont("s" this.previewFontSize " Bold c0067C0", "Microsoft YaHei UI")
      } else {
        previewGui.SetFont("s" this.previewFontSize " Norm c202020", "Microsoft YaHei UI")
      }

      previewGui.Add("Text", "xm y+4 w" prefixWidth " Right", prefixText)
      previewGui.Add("Text", "x+8 yp w" labelWidth, lineText)
    }

    if (hwnds.Length > maxItems) {
      previewGui.SetFont("s" this.previewFontSize " Norm c606060", "Microsoft YaHei UI")
      previewGui.Add("Text", "xm y+4 w" prefixWidth " Right", "")
      previewGui.Add("Text", "x+8 yp w" labelWidth, "... +" (hwnds.Length - maxItems))
    }

    previewGui.Show("NoActivate Hide AutoSize")

    previewSize := this.getWindowSize(previewGui.Hwnd)
    position := this.getCenteredPreviewPosition(previewSize.width, previewSize.height)
    previewGui.Show("NoActivate x" position.x " y" position.y)

    this.previewGui := previewGui
    SetTimer(this.hidePreviewCallback, -Round(this.previewSeconds * 1000))
  }

  ; 隐藏窗口切换预览。
  ; 每次显示新预览前先销毁旧预览，避免连续切换时残留多个窗口。
  hideWindowPreview() {
    try {
      if IsObject(this.previewGui) {
        this.previewGui.Destroy()
      }
    }

    this.previewGui := ""
  }

  ; 读取窗口尺寸。
  ; 预览 GUI 初次 AutoSize 时处于隐藏状态，WinGetPos 默认查不到隐藏窗口，因此用 GetWindowRect 直接读取。
  getWindowSize(hwnd) {
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rect) {
      return {
        width: this.previewWidth,
        height: 240
      }
    }

    return {
      width: NumGet(rect, 8, "int") - NumGet(rect, 0, "int"),
      height: NumGet(rect, 12, "int") - NumGet(rect, 4, "int")
    }
  }

  ; 计算预览窗口在当前活动窗口所在屏幕的居中位置。
  getCenteredPreviewPosition(previewWidth, previewHeight) {
    activeHwnd := WinExist("A")

    try {
      WinGetPos(&activeX, &activeY, &activeWidth, &activeHeight, this.toWinId(activeHwnd))
      centerX := activeX + activeWidth / 2
      centerY := activeY + activeHeight / 2
    } catch Error {
      MouseGetPos(&centerX, &centerY)
    }

    monitorIndex := this.getMonitorIndexAt(centerX, centerY)
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)

    return {
      x: Round(left + ((right - left - previewWidth) / 2)),
      y: Round(top + ((bottom - top - previewHeight) / 2))
    }
  }

  ; 根据坐标查找所在显示器。
  ; 找不到时回退到主显示器，保证预览一定能显示出来。
  getMonitorIndexAt(x, y) {
    monitorCount := MonitorGetCount()

    Loop monitorCount {
      MonitorGet(A_Index, &left, &top, &right, &bottom)
      if (x >= left && x < right && y >= top && y < bottom) {
        return A_Index
      }
    }

    return 1
  }

  ; 生成窗口预览列表中的单行描述。
  ; 标题过长时截断，并追加进程名帮助区分同名窗口。
  getWindowLabel(hwnd) {
    winId := this.toWinId(hwnd)

    try {
      title := WinGetTitle(winId)
      processName := WinGetProcessName(winId)
    } catch Error {
      return this.toWinId(hwnd)
    }

    title := StrReplace(title, "`r", " ")
    title := StrReplace(title, "`n", " ")
    if (StrLen(title) > 56) {
      title := SubStr(title, 1, 53) "..."
    }

    return title " [" processName "]"
  }

  ; 判断窗口是否适合参与全局窗口切换。
  ; 排除桌面、任务栏、工具窗口、隐藏窗口和空标题窗口。
  isSwitchableWindow(hwnd) {
    winId := this.toWinId(hwnd)

    if !WinExist(winId) {
      return false
    }

    try {
      title := WinGetTitle(winId)
      className := WinGetClass(winId)
      processName := WinGetProcessName(winId)
      style := WinGetStyle(winId)
      exStyle := WinGetExStyle(winId)
    } catch Error {
      return false
    }

    if (title = "") {
      return false
    }

    if this.isIgnoredWindow(title, processName) {
      return false
    }

    if !(style & 0x10000000) {
      return false
    }

    ; WS_EX_TOOLWINDOW 通常是浮动工具窗，不应该参与主窗口切换。
    if (exStyle & 0x80) {
      return false
    }

    switch className {
      case "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd":
        return false
    }

    return true
  }

  ; 排除不应出现在窗口切换列表里的后台辅助窗口。
  ; 例如 Chromium/Electron 应用的 crashpad_handler.exe 可能短暂创建可见窗口，但不是用户可操作窗口。
  isIgnoredWindow(title, processName) {
    normalizedTitle := StrLower(title)
    normalizedProcessName := StrLower(processName)

    if (normalizedProcessName = "crashpad_handler.exe" || normalizedProcessName = "crashpad-handler.exe") {
      return true
    }

    return InStr(normalizedTitle, "crashpad") != 0
  }

  ; 显示、恢复并激活指定窗口。
  ; 最小化窗口会先恢复，保证切换后能看到目标窗口。
  focusWindow(hwnd) {
    winId := this.toWinId(hwnd)

    try {
      if (WinGetMinMax(winId) = -1) {
        WinRestore(winId)
      }

      WinActivate(winId)
      WinWaitActive(winId, , this.waitSeconds)
      return WinActive(winId) != 0
    } catch Error {
      return false
    }
  }

  ; 把裸 hwnd 转成 AHK WinTitle 可识别的 ahk_id 表达式。
  toWinId(hwnd) {
    return "ahk_id " hwnd
  }
}
