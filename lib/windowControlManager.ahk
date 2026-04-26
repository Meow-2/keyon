; 通用窗口管理快捷键。
; 负责关闭当前窗口，以及在当前桌面可管理窗口之间向前/向后切换。
class windowControlManager {
  __New(configPath) {
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
    this.previewSize := ""
    this.previewRowBars := []
    this.previewRowTexts := []
    this.hidePreviewCallback := ObjBindMethod(this, "hideWindowPreview")
    this.hideManagedPreviewOnWinReleaseCallback := ObjBindMethod(this, "hideManagedPreviewWhenWinReleased")
    this.systemSwitchActive := false
    this.systemCycleHotkeys := [
      { hotkey: this.buildSystemCycleKey(this.nextHotkey), callback: ObjBindMethod(this, "continueSystemWindowSwitch", 1) },
      { hotkey: this.buildSystemCycleKey(this.previousHotkey), callback: ObjBindMethod(this, "continueSystemWindowSwitch", -1) }
    ]
    this.finishSystemSwitchCallback := ObjBindMethod(this, "finishSystemWindowSwitchWhenWinReleased")
  }

  ; 注册启用的窗口管理快捷键。
  ; 单个快捷键为空时跳过，避免未配置字段影响其他工具快捷键。
  registerHotkeys() {
    if !this.enabled {
      return 0
    }

    registeredCount := 0
    for hotkeyItem in this.getPrimaryHotkeyItems() {
      registeredCount += this.registerHotkey(hotkeyItem.hotkey, hotkeyItem.callback, hotkeyItem.actionName)
    }

    return registeredCount
  }

  ; 返回窗口管理主热键定义，便于统一注册。
  getPrimaryHotkeyItems() {
    return [
      { hotkey: this.closeHotkey, callback: ObjBindMethod(this, "closeActiveWindow"), actionName: "关闭窗口" },
      { hotkey: this.nextHotkey, callback: ObjBindMethod(this, "activateAdjacentWindow", 1), actionName: "切换到下一个窗口" },
      { hotkey: this.previousHotkey, callback: ObjBindMethod(this, "activateAdjacentWindow", -1), actionName: "切换到上一个窗口" }
    ]
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
      WinClose(windowHelper.toWinId(activeHwnd))
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

    targetIndex := this.getAdjacentWindowIndex(hwnds, WinExist("A"), direction)
    this.showWindowPreview(hwnds, targetIndex, this.shouldHidePreviewOnWinRelease(A_ThisHotkey))
    return this.focusWindow(hwnds[targetIndex])
  }

  ; 计算当前活动窗口在循环列表中的相邻目标位置。
  ; 当前没有活动窗口命中列表时回退到第一项。
  getAdjacentWindowIndex(hwnds, activeHwnd, direction) {
    activeIndex := 0
    for index, hwnd in hwnds {
      if (hwnd = activeHwnd) {
        activeIndex := index
        break
      }
    }

    if (activeIndex = 0) {
      return 1
    }

    targetIndex := activeIndex + direction
    if (targetIndex < 1) {
      return hwnds.Length
    }

    if (targetIndex > hwnds.Length) {
      return 1
    }

    return targetIndex
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
      this.setSystemSwitchSession(true)
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

    this.setSystemSwitchSession(false)
  }

  ; 统一启停 system 模式的 Alt+Tab 会话状态。
  ; 开启时按下 Alt 并接管裸 J/K；关闭时释放 Alt 并取消接管。
  setSystemSwitchSession(isActive) {
    SetTimer(this.finishSystemSwitchCallback, 0)

    if isActive {
      Send("{Alt down}")
      this.systemSwitchActive := true
      this.setSystemCycleHotkeys("On")
      SetTimer(this.finishSystemSwitchCallback, 20)
      return
    }

    if !this.systemSwitchActive {
      return
    }

    Send("{Alt up}")
    this.systemSwitchActive := false
    this.setSystemCycleHotkeys("Off")
  }

  ; 批量启停 system 切换会话内的裸按键接管。
  ; 只在 Alt+Tab 界面打开期间启用，避免平时拦截用户正常输入 J/K。
  setSystemCycleHotkeys(state) {
    for item in this.systemCycleHotkeys {
      this.setSystemCycleHotkey(item.hotkey, item.callback, state)
    }
  }

  ; 动态启停单个临时热键。
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
      if windowHelper.arrayHas(currentHwnds, hwnd) {
        cycleHwnds.Push(hwnd)
      }
    }

    for hwnd in currentHwnds {
      if !windowHelper.arrayHas(cycleHwnds, hwnd) {
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
  ; 使用居中的轻量 GUI 作为预览，当前目标通过列表选中态高亮。
  showWindowPreview(hwnds, targetIndex, hideOnWinRelease := false) {
    if (this.previewSeconds <= 0) {
      return
    }

    this.ensurePreviewGui()
    visibleRowCount := this.updatePreviewList(hwnds, targetIndex)

    estimatedSize := this.buildPreviewWindowSize(visibleRowCount)
    position := this.getCenteredPreviewPosition(estimatedSize.width, estimatedSize.height)
    this.previewGui.Show("NoActivate w" estimatedSize.width " h" estimatedSize.height " x" position.x " y" position.y)

    actualSize := this.getWindowSize(this.previewGui.Hwnd)
    if (actualSize.width != estimatedSize.width || actualSize.height != estimatedSize.height) {
      actualPosition := this.getCenteredPreviewPosition(actualSize.width, actualSize.height)
      this.previewGui.Show("NoActivate x" actualPosition.x " y" actualPosition.y)
    }

    this.schedulePreviewHide(hideOnWinRelease)
  }

  ; 隐藏窗口切换预览。
  ; 预览窗口常驻复用，只隐藏不销毁，避免连续切换时反复创建顶层 GUI。
  hideWindowPreview() {
    SetTimer(this.hidePreviewCallback, 0)
    SetTimer(this.hideManagedPreviewOnWinReleaseCallback, 0)

    try if IsObject(this.previewGui) {
      this.previewGui.Hide()
    }
  }

  ; Win 组合键触发的 managed 预览在松开 Win 时应立即消失。
  ; 只在物理 Win 当前仍按下时启用，避免普通单次切换误触发这条路径。
  hideManagedPreviewWhenWinReleased() {
    if this.isWinPhysicallyDown() {
      return
    }

    this.hideWindowPreview()
  }

  ; 只有由 Win 修饰键触发且当前仍按住物理 Win 时，才需要在松开 Win 后立刻隐藏预览。
  shouldHidePreviewOnWinRelease(hotkeyName) {
    return this.isWinPhysicallyDown() && this.isWinModifierHotkey(hotkeyName)
  }

  ; 按当前触发方式安排预览隐藏时机。
  ; Win 组合键驱动的 managed 会话由 Win 键生命周期控制，其余情况仍使用超时隐藏。
  schedulePreviewHide(hideOnWinRelease) {
    SetTimer(this.hidePreviewCallback, 0)
    SetTimer(this.hideManagedPreviewOnWinReleaseCallback, 0)

    if hideOnWinRelease {
      SetTimer(this.hideManagedPreviewOnWinReleaseCallback, 20)
      return
    }

    SetTimer(this.hidePreviewCallback, -Round(this.previewSeconds * 1000))
  }

  ; 判断热键字符串是否带 Win 修饰键。
  isWinModifierHotkey(hotkeyName) {
    return InStr(hotkeyName, "#")
  }

  ; 预创建窗口切换预览 GUI。
  ; 预览使用单个常驻 GUI 和固定数量的行控件，只刷新文本和显隐状态。
  ensurePreviewGui() {
    if IsObject(this.previewGui) {
      return
    }

    rowCount := Max(3, this.previewMaxItems + 2)
    rowHeight := this.getPreviewRowHeight()
    textWidth := this.previewWidth - 28

    previewGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border")
    previewGui.BackColor := "202020"
    previewGui.MarginX := 24
    previewGui.MarginY := 18
    previewGui.SetFont("cF5F5F5 s" this.previewFontSize, "Microsoft YaHei UI")
    previewGui.Add("Text", "xm ym w" this.previewWidth " cF5F5F5", "窗口切换")

    this.previewRowBars := []
    this.previewRowTexts := []
    Loop rowCount {
      rowOptions := A_Index = 1
        ? "xm y+10 w" this.previewWidth " h" rowHeight " Disabled -Smooth Background202020 c202020 Hidden"
        : "xm y+6 w" this.previewWidth " h" rowHeight " Disabled -Smooth Background202020 c202020 Hidden"
      rowBar := previewGui.Add("Progress", rowOptions, 100)
      rowText := previewGui.Add("Text", "xp+14 yp+4 w" textWidth " h" (rowHeight - 8) " BackgroundTrans cF5F5F5 Hidden", "")
      this.previewRowBars.Push(rowBar)
      this.previewRowTexts.Push(rowText)
    }

    this.previewSize := this.buildPreviewWindowSize(rowCount)
    previewGui.Show("NoActivate Hide w" this.previewSize.width " h" this.previewSize.height)
    this.applyPreviewWindowStyle(previewGui)

    this.previewGui := previewGui
  }

  ; 按当前切换目标刷新预览列表。
  ; 目标窗口尽量保持在可视区域中部，顶部和底部用省略行表示还有更多候选。
  updatePreviewList(hwnds, targetIndex) {
    previewRange := this.getPreviewRange(hwnds.Length, targetIndex)
    startIndex := previewRange.startIndex
    endIndex := previewRange.endIndex
    rowTexts := []
    if (startIndex > 1) {
      rowTexts.Push("... +" (startIndex - 1))
    }

    Loop (endIndex - startIndex + 1) {
      index := startIndex + A_Index - 1
      rowTexts.Push(index ". " this.getWindowLabel(hwnds[index]))
    }

    if (endIndex < hwnds.Length) {
      rowTexts.Push("... +" (hwnds.Length - endIndex))
    }

    selectedRow := targetIndex - startIndex + 1
    if (startIndex > 1) {
      selectedRow += 1
    }

    this.renderPreviewRows(rowTexts, selectedRow)
    return rowTexts.Length
  }

  ; 计算预览面板中实际显示的窗口范围。
  ; 尽量让目标窗口处于中间位置，必要时向头尾收缩。
  getPreviewRange(totalCount, targetIndex) {
    maxItems := Min(this.previewMaxItems, totalCount)
    startIndex := Max(1, targetIndex - Floor(maxItems / 2))
    endIndex := startIndex + maxItems - 1

    if (endIndex > totalCount) {
      endIndex := totalCount
      startIndex := Max(1, endIndex - maxItems + 1)
    }

    return {
      startIndex: startIndex,
      endIndex: endIndex
    }
  }

  ; 根据当前候选内容刷新固定行控件。
  ; 选中行用天蓝色背景，其余行保持透明深色背景。
  renderPreviewRows(rowTexts, selectedRow) {
    static normalColor := "202020"
    static selectedColor := "66BFFF"
    static normalTextColor := "F5F5F5"
    static selectedTextColor := "101418"

    rowCount := this.previewRowBars.Length
    Loop rowCount {
      rowBar := this.previewRowBars[A_Index]
      rowText := this.previewRowTexts[A_Index]

      if (A_Index <= rowTexts.Length) {
        rowBar.Opt(A_Index = selectedRow ? "c" selectedColor : "c" normalColor)
        rowBar.Opt("-Hidden")
        rowText.Value := rowTexts[A_Index]
        rowText.SetFont("c" (A_Index = selectedRow ? selectedTextColor : normalTextColor))
        rowText.Opt("-Hidden")
      } else {
        rowBar.Opt("Hidden")
        rowText.Opt("Hidden")
      }
    }
  }

  ; 按当前字体大小估算单行预览高度。
  ; 维持较宽松的留白，让 Mica 面板上的候选列表更接近系统弹窗观感。
  getPreviewRowHeight() {
    return Max(28, this.previewFontSize + 16)
  }

  ; 计算预览窗口尺寸。
  ; 不再依赖首次 AutoSize，避免隐藏行控件导致窗口高度只按标题计算。
  buildPreviewWindowSize(visibleRowCount) {
    rowHeight := this.getPreviewRowHeight()
    titleHeight := Max(26, this.previewFontSize + 10)
    rowGap := 6
    firstRowGap := 10
    contentHeight := titleHeight

    if (visibleRowCount > 0) {
      contentHeight += firstRowGap + (visibleRowCount * rowHeight) + (Max(0, visibleRowCount - 1) * rowGap)
    }

    return {
      width: this.previewWidth + (24 * 2) + 2,
      height: contentHeight + (18 * 2) + 2
    }
  }

  ; 给预览窗口应用 Windows 11 风格外观。
  ; 优先启用 Mica 背景、沉浸式深色模式和圆角；不支持时静默回退到普通深色面板。
  applyPreviewWindowStyle(previewGui) {
    windowHelper.applyMicaWindowStyle(previewGui.Hwnd)
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
    return windowHelper.getCenteredPosition(previewWidth, previewHeight)
  }

  ; 生成窗口预览列表中的单行描述。
  ; 标题过长时截断，并追加进程名帮助区分同名窗口。
  getWindowLabel(hwnd) {
    winId := windowHelper.toWinId(hwnd)

    try {
      title := WinGetTitle(winId)
      processName := WinGetProcessName(winId)
    } catch Error {
      return windowHelper.toWinId(hwnd)
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
    winId := windowHelper.toWinId(hwnd)

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
    winId := windowHelper.toWinId(hwnd)

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

}
