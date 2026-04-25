; 单个应用快捷键配置的内存结构。
; 只负责保存从 config/apps.ini 读取出的配置，不包含业务逻辑。
class appRule {
  ; 初始化一条应用规则。
  ; name 是 INI section 名称；hotkey 是 AHK 快捷键；winTitle 用于匹配窗口；matchMode 控制窗口匹配方式；target 用于启动应用。
  __New(name, hotkey, winTitle, matchMode, target, args, workingDir, processName, wakeHotkey, detectHidden, waitSeconds, runAsAdmin) {
    this.name := name
    this.hotkey := hotkey
    this.winTitle := winTitle
    this.matchMode := matchMode
    this.target := target
    this.args := args
    this.workingDir := workingDir
    this.processName := processName
    this.wakeHotkey := wakeHotkey
    this.detectHidden := detectHidden
    this.waitSeconds := waitSeconds
    this.runAsAdmin := runAsAdmin
  }
}

; 应用窗口管理器。
; 负责读取应用配置、注册快捷键，并在快捷键触发时执行启动、呼出、窗口切换和聚焦。
class appWindowManager {
  ; 保存配置路径，并在创建对象时立即读取所有可用应用规则。
  __New(configPath) {
    this.configPath := configPath
    this.config := configReader(configPath)
    this.appRules := this.loadAppRules()
  }

  ; 注册 config/apps.ini 中所有启用的应用快捷键。
  ; 返回成功注册的快捷键数量；单个快捷键注册失败时只提示错误，不影响其他快捷键。
  registerHotkeys() {
    registeredCount := 0

    for currentRule in this.appRules {
      try {
        Hotkey(currentRule.hotkey, ObjBindMethod(this, "handleAppHotkey", currentRule), "On")
        registeredCount += 1
      } catch Error as err {
        MsgBox("快捷键注册失败：" currentRule.name "`n" err.Message, "mine-key")
      }
    }

    return registeredCount
  }

  ; 应用快捷键的统一入口。
  ; 执行顺序是：优先切换可见窗口，其次恢复可呼出的窗口，再尝试后台唤醒，最后启动应用。
  handleAppHotkey(currentRule, *) {
    if (currentRule.winTitle != "") {
      visibleHwnds := this.findManagedWindows(currentRule, true)
      if (visibleHwnds.Length) {
        targetHwnd := this.pickNextWindow(visibleHwnds)
        this.focusWindow(targetHwnd, currentRule.waitSeconds)
        return
      }

      callableHwnds := this.findManagedWindows(currentRule, false)
      if (callableHwnds.Length) {
        this.focusWindow(callableHwnds[1], currentRule.waitSeconds)
        return
      }
    }

    if (this.tryWakeExistingProcess(currentRule)) {
      return
    }

    this.runApplication(currentRule)
  }

  ; 从 INI 文件读取应用规则。
  ; 只加载 enabled=true、hotkey 不为空、且 winTitle 或 target 至少有一个的配置。
  loadAppRules() {
    appRules := []

    if !FileExist(this.configPath) {
      return appRules
    }

    try {
      sectionNames := IniRead(this.configPath)
    } catch Error {
      return appRules
    }

    for sectionName in StrSplit(sectionNames, "`n", "`r") {
      sectionName := Trim(sectionName)
      if (sectionName = "") {
        continue
      }

      if !this.config.readBool(sectionName, "enabled", true) {
        continue
      }

      hotkey := this.config.readText(sectionName, "hotkey")
      winTitle := this.config.readText(sectionName, "winTitle")
      target := this.config.readText(sectionName, "target")

      if (hotkey = "" || (winTitle = "" && target = "")) {
        continue
      }

      appRules.Push(appRule(
        sectionName,
        hotkey,
        winTitle,
        this.normalizeMatchMode(this.config.readText(sectionName, "matchMode", "contains")),
        target,
        this.config.readText(sectionName, "args"),
        this.config.readText(sectionName, "workingDir"),
        this.config.readText(sectionName, "processName"),
        this.config.readText(sectionName, "wakeHotkey"),
        this.config.readBool(sectionName, "detectHidden", false),
        this.config.readNumber(sectionName, "waitSeconds", 3),
        this.config.readBool(sectionName, "runAsAdmin", false)
      ))
    }

    return appRules
  }

  ; 查找当前应用可管理的窗口。
  ; onlyVisible=true 时只返回桌面上可见且未最小化的窗口；false 时返回可被呼出的可用窗口。
  findManagedWindows(currentRule, onlyVisible := false) {
    includeHidden := onlyVisible ? false : currentRule.detectHidden
    hwnds := this.findWindows(currentRule.winTitle, includeHidden, currentRule.matchMode)
    managedHwnds := []

    for hwnd in hwnds {
      if (onlyVisible ? this.isVisibleOnDesktop(hwnd) : this.isUsableWindow(hwnd)) {
        managedHwnds.Push(hwnd)
      }
    }

    return managedHwnds
  }

  ; 使用 AHK WinTitle 表达式枚举窗口句柄。
  ; includeHidden 会临时切换 DetectHiddenWindows，matchMode 会临时切换 SetTitleMatchMode。
  ; 函数结束后恢复原设置，避免某个应用的匹配方式影响其他配置。
  findWindows(winTitle, includeHidden := false, matchMode := "contains") {
    if (winTitle = "") {
      return []
    }

    previousDetectHiddenWindows := A_DetectHiddenWindows
    previousTitleMatchMode := A_TitleMatchMode
    DetectHiddenWindows(includeHidden)
    SetTitleMatchMode(this.toAhkTitleMatchMode(matchMode))

    try {
      hwnds := WinGetList(winTitle)
    } catch Error {
      hwnds := []
    }

    DetectHiddenWindows(previousDetectHiddenWindows)
    SetTitleMatchMode(previousTitleMatchMode)
    return hwnds
  }

  ; 等待某条规则匹配到窗口。
  ; WinWait 也依赖当前 TitleMatchMode，因此这里和 findWindows 一样临时切换匹配模式。
  waitForWindow(currentRule) {
    if (currentRule.winTitle = "") {
      return false
    }

    previousDetectHiddenWindows := A_DetectHiddenWindows
    previousTitleMatchMode := A_TitleMatchMode
    DetectHiddenWindows(currentRule.detectHidden)
    SetTitleMatchMode(this.toAhkTitleMatchMode(currentRule.matchMode))

    try {
      exists := WinWait(currentRule.winTitle, , currentRule.waitSeconds)
    } catch Error {
      exists := 0
    }

    DetectHiddenWindows(previousDetectHiddenWindows)
    SetTitleMatchMode(previousTitleMatchMode)
    return exists != 0
  }

  ; 判断窗口是否适合被管理。
  ; 当前标准是窗口仍然存在，并且标题不为空；空标题窗口通常是内部窗口或不可交互窗口。
  isUsableWindow(hwnd) {
    winId := this.toWinId(hwnd)
    return WinExist(winId) && WinGetTitle(winId) != ""
  }

  ; 判断窗口是否已经显示在桌面上。
  ; 注意：被其他窗口遮挡但自身可见、未最小化的窗口仍算“显示在桌面上”。
  isVisibleOnDesktop(hwnd) {
    if !this.isUsableWindow(hwnd) {
      return false
    }

    winId := this.toWinId(hwnd)
    style := WinGetStyle(winId)

    ; WS_VISIBLE 表示窗口处于可见状态；最小化窗口虽然存在，但不算显示在桌面上。
    return (style & 0x10000000) && WinGetMinMax(winId) != -1
  }

  ; 从一组同应用窗口中选出本次要激活的窗口。
  ; 如果当前活动窗口属于这组窗口，则切到下一个；否则切到第一个匹配窗口。
  pickNextWindow(hwnds) {
    activeHwnd := WinExist("A")

    for index, hwnd in hwnds {
      if (hwnd = activeHwnd) {
        nextIndex := index = hwnds.Length ? 1 : index + 1
        return hwnds[nextIndex]
      }
    }

    return hwnds[1]
  }

  ; 显示、恢复并激活指定窗口。
  ; 返回是否成功让该窗口成为活动窗口；失败时返回 false，不抛出异常中断脚本。
  focusWindow(hwnd, waitSeconds := 3) {
    winId := this.toWinId(hwnd)

    if !WinExist(winId) {
      return false
    }

    try {
      WinShow(winId)
    }

    try {
      if (WinGetMinMax(winId) = -1) {
        WinRestore(winId)
      }
    }

    try {
      WinActivate(winId)
      WinWaitActive(winId, , waitSeconds)
      return WinActive(winId) != 0
    } catch Error {
      return false
    }
  }

  ; 尝试唤醒已经存在但没有普通可见窗口的后台进程。
  ; 适用于托盘应用：通过 processName 判断进程存在，再发送 wakeHotkey 呼出窗口。
  tryWakeExistingProcess(currentRule) {
    if (currentRule.processName = "" || currentRule.wakeHotkey = "") {
      return false
    }

    if !ProcessExist(currentRule.processName) {
      return false
    }

    Send(currentRule.wakeHotkey)

    if (currentRule.winTitle = "") {
      return true
    }

    if !this.waitForWindow(currentRule) {
      return false
    }

    callableHwnds := this.findManagedWindows(currentRule, false)
    if !callableHwnds.Length {
      return false
    }

    return this.focusWindow(callableHwnds[1], currentRule.waitSeconds)
  }

  ; 启动应用，并在启动后尽量等待和聚焦匹配窗口。
  ; 如果没有配置 winTitle，则只负责启动 target，不尝试后续窗口匹配。
  runApplication(currentRule) {
    if (currentRule.target = "") {
      return false
    }

    workingDir := currentRule.workingDir != "" ? currentRule.workingDir : A_ScriptDir

    try {
      this.runConfiguredTarget(currentRule, workingDir)
    } catch Error as err {
      MsgBox("应用启动失败：" currentRule.name "`n" err.Message, "mine-key")
      return false
    }

    if (currentRule.winTitle = "") {
      return true
    }

    if !this.waitForWindow(currentRule) {
      return false
    }

    visibleHwnds := this.findManagedWindows(currentRule, true)
    if (visibleHwnds.Length) {
      return this.focusWindow(visibleHwnds[1], currentRule.waitSeconds)
    }

    callableHwnds := this.findManagedWindows(currentRule, false)
    if (callableHwnds.Length) {
      return this.focusWindow(callableHwnds[1], currentRule.waitSeconds)
    }

    return false
  }

  ; 根据配置启动目标应用。
  ; runAsAdmin=false 时通过普通权限 Explorer 代理启动，避免管理员权限的 mine-key 把子进程也带成管理员。
  runConfiguredTarget(currentRule, workingDir) {
    if currentRule.runAsAdmin {
      runTarget := currentRule.target
      if (runTarget != "" && SubStr(runTarget, 1, 1) != '"' && InStr(runTarget, " ") && !RegExMatch(runTarget, "i)^[a-z][a-z0-9+.-]*:")) {
        runTarget := '"' runTarget '"'
      }

      if (currentRule.args != "") {
        runTarget .= " " currentRule.args
      }

      Run("*RunAs " runTarget, workingDir)
      return
    }

    this.shellRun(currentRule.target, currentRule.args, workingDir)
  }

  ; 通过桌面 Explorer 的 ShellExecute 启动程序。
  ; Explorer 通常运行在普通用户完整性级别，所以管理员脚本调用它时可以把新应用降回普通权限。
  shellRun(target, args := "", workingDir := "") {
    static VT_UI4 := 0x13
    static SWC_DESKTOP := ComValue(VT_UI4, 0x8)

    shellApplication := ComObject("Shell.Application").Windows.Item(SWC_DESKTOP).Document.Application
    shellApplication.ShellExecute(target, args, workingDir, "open", 1)
  }

  ; 把裸 hwnd 转成 AHK WinTitle 可识别的 ahk_id 表达式。
  ; 统一封装后，调用 WinExist/WinActivate/WinShow 时不容易漏写前缀。
  toWinId(hwnd) {
    return "ahk_id " hwnd
  }

  ; 统一配置里的窗口匹配方式。
  ; 默认 contains 对普通窗口标题和 ahk_exe 最友好；regex 只在明确需要正则时使用。
  normalizeMatchMode(matchMode) {
    matchMode := StrLower(Trim(matchMode))

    switch matchMode {
      case "contains", "contain", "2", "":
        return "contains"
      case "exact", "3":
        return "exact"
      case "startswith", "startsWith", "prefix", "1":
        return "startsWith"
      case "regex", "regexp", "regular":
        return "regex"
      default:
        return "contains"
    }
  }

  ; 把项目配置值转换成 AHK SetTitleMatchMode 接受的值。
  ; AHK 支持 1=开头匹配、2=包含匹配、3=精确匹配、RegEx=正则匹配。
  toAhkTitleMatchMode(matchMode) {
    switch this.normalizeMatchMode(matchMode) {
      case "contains":
        return 2
      case "exact":
        return 3
      case "startsWith":
        return 1
      case "regex":
        return "RegEx"
      default:
        return 2
    }
  }
}
