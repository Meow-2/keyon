; 单个输入法状态切换快捷键的内存结构。
; 只保存热键、目标状态和是否透传原按键，不直接执行切换。
class imeHotkeyRule {
  ; 初始化一条输入法快捷键规则。
  ; targetState 支持 CN、EN、TOGGLE；scopeProcessNames 支持把同一热键限定到多个 app。
  __New(name, hotkey, targetState, passThrough, switchMethod, sendAfterSwitch, scopeProcessNames) {
    this.name := name
    this.hotkey := hotkey
    this.targetState := targetState
    this.passThrough := passThrough
    this.switchMethod := switchMethod
    this.sendAfterSwitch := sendAfterSwitch
    this.scopeProcessNames := scopeProcessNames
  }
}

; 单个应用默认输入法状态规则的内存结构。
; 只保留 toEnglish/toChinese 两组规则，目标状态由 section 名称决定。
class imeAppDefaultRule {
  __New(name, targetState, processNames, switchMethod) {
    this.name := name
    this.targetState := targetState
    this.processNames := processNames
    this.switchMethod := switchMethod

    ; 复用 switchToState() 时需要这些字段，自动切换场景不透传也没有触发热键。
    this.passThrough := false
    this.hotkey := ""
  }
}

; 输入法状态管理器。
; 负责读取 config/ime.ini、注册状态切换快捷键、检测当前输入法状态并切换到目标状态。
class imeManager {
  ; 读取通用配置和快捷键规则。
  ; profile 决定默认中文转换码；switchMethod 决定使用 DLL 还是模拟按键切换。
  __New(configPath) {
    this.config := configReader(configPath)
    this.enabled := this.config.readBool("general", "enabled", true)
    this.profile := this.config.readText("general", "profile", "microsoftPinyin")
    this.switchMethod := this.normalizeSwitchMethod(this.config.readText("general", "switchMethod", "dll"))
    this.checkTimeout := this.config.readNumber("general", "checkTimeout", 500)
    this.cnConversionMode := this.config.readNumber("general", "cnConversionMode", this.getDefaultCnConversionMode())
    this.appDefaultsEnabled := this.config.readBool("appDefaults", "enabled", false)
    this.appDefaultInterval := Max(50, this.config.readNumber("appDefaults", "interval", 100))
    this.appDefaultFocusDelay := Max(0, this.config.readNumber("appDefaults", "focusDelay", 80))
    this.hotkeyRules := this.loadHotkeyRules()
    this.appDefaultRules := this.loadAppDefaultRules()
    this.appDefaultRuleByProcessName := this.buildAppDefaultRuleIndex()
    this.lastAppDefaultProcessName := ""
    this.appDefaultChecking := false
    this.checkAppDefaultCallback := ObjBindMethod(this, "checkAppDefaultState")
  }

  ; 注册所有启用的输入法状态切换快捷键。
  ; 如果 general.enabled=false，则整个输入法模块不注册任何快捷键。
  registerHotkeys() {
    if !this.enabled {
      return 0
    }

    registeredCount := 0

    for currentRule in this.hotkeyRules {
      hotkeyName := this.buildHotkeyName(currentRule.hotkey, currentRule.passThrough)
      try {
        Hotkey(hotkeyName, ObjBindMethod(this, "handleStateHotkey", currentRule), "On")
        registeredCount += 1
      } catch Error as err {
        MsgBox("输入法快捷键注册失败：" currentRule.name "`n" err.Message, "keyon")
      }
    }

    registeredCount += this.startAppDefaultWatcher()

    return registeredCount
  }

  ; 输入法快捷键触发入口。
  ; currentRule 会被继续传入，用于判断 passThrough、切换方式和切换后的补发按键。
  handleStateHotkey(currentRule, *) {
    if !this.isHotkeyActiveForCurrentWindow(currentRule) {
      return
    }

    if this.canManageInputState() {
      this.switchToState(currentRule.targetState, currentRule)
    }

    this.sendAfterSwitch(currentRule)
  }

  ; 将当前输入法切换到指定目标状态。
  ; 会先检测当前状态；如果已经是目标状态，就不再执行额外切换。
  switchToState(targetState, currentRule := "") {
    targetState := this.normalizeTargetState(targetState)
    if (targetState = "") {
      return false
    }

    currentState := this.getInputState()
    if (targetState = "TOGGLE") {
      targetState := currentState = "CN" ? "EN" : "CN"
    }

    if (currentState = targetState) {
      return true
    }

    switchMethod := IsObject(currentRule) && currentRule.switchMethod != "" ? currentRule.switchMethod : this.switchMethod

    switch switchMethod {
      case "dll":
        return this.setInputStateByDll(targetState)
      case "lShift":
        if this.shouldTrustPassThroughKey(currentRule, "lShift", targetState) {
          return true
        }
        return this.toggleStateBySend("{LShift}", targetState)
      case "rShift":
        if this.shouldTrustPassThroughKey(currentRule, "rShift", targetState) {
          return true
        }
        return this.toggleStateBySend("{RShift}", targetState)
      case "ctrlSpace":
        if this.shouldTrustPassThroughKey(currentRule, "ctrlSpace", targetState) {
          return true
        }
        return this.toggleStateBySend("{Ctrl Down}{Space}{Ctrl Up}", targetState)
      default:
        return false
    }
  }

  ; 获取当前输入法状态。
  ; 返回 CN 或 EN；读取失败时保守返回 EN，避免误判为中文后跳过切换。
  getInputState(hwnd := 0) {
    hwnd := hwnd ? hwnd : this.getFocusedWindow()
    if !hwnd {
      return "EN"
    }

    openStatus := this.getOpenStatus(hwnd)
    if !openStatus {
      return "EN"
    }

    conversionMode := this.getConversionMode(hwnd)
    return (conversionMode & 1) ? "CN" : "EN"
  }

  ; 判断当前焦点窗口的输入法状态是否可读、可控。
  ; 不可控时直接跳过切换逻辑，避免在游戏或特殊窗口里先执行一段注定失败的状态切换。
  canManageInputState(hwnd := 0) {
    hwnd := hwnd ? hwnd : this.getFocusedWindow()
    if !hwnd {
      return false
    }

    openStatusResult := this.tryImeControl(hwnd, 0x5)
    if !openStatusResult.ok {
      return false
    }

    if !openStatusResult.value {
      return true
    }

    return this.tryImeControl(hwnd, 0x1).ok
  }

  ; 通过 Windows IMM 接口直接设置输入法状态。
  ; CN 会打开输入法并写入中文转换码；EN 会关闭输入法打开状态。
  setInputStateByDll(targetState) {
    hwnd := this.getFocusedWindow()
    if !hwnd {
      return false
    }

    if (targetState = "CN") {
      this.setOpenStatus(true, hwnd)
      this.setConversionMode(this.cnConversionMode, hwnd)
    } else if (targetState = "EN") {
      this.setOpenStatus(false, hwnd)
    } else {
      return false
    }

    Sleep(30)
    return this.getInputState(hwnd) = targetState
  }

  ; 通过模拟按键切换输入法状态。
  ; 适用于 DLL 方式在某些输入法或窗口里不稳定时的替代方案。
  toggleStateBySend(sendText, targetState) {
    SendInput(sendText)
    Sleep(50)
    return this.getInputState() = targetState
  }

  ; 判断是否应该信任已经透传出去的原按键。
  ; 例如 RShift 本身就会切换输入法，且 passThrough=true 时，不应再额外模拟一次 RShift。
  shouldTrustPassThroughKey(currentRule, switchMethod, targetState) {
    if !IsObject(currentRule) || !currentRule.passThrough {
      return false
    }

    if !this.hotkeyMatchesSwitchMethod(currentRule.hotkey, switchMethod) {
      return false
    }

    ; 透传的原始按键可能已经完成了切换，避免再模拟同一个切换键造成二次切换。
    Sleep(80)
    return this.getInputState() = targetState
  }

  ; 判断触发热键是否就是当前切换方式使用的按键。
  ; 只处理常见的 LShift、RShift、Ctrl+Space，避免复杂热键误判。
  hotkeyMatchesSwitchMethod(hotkey, switchMethod) {
    normalizedHotkey := StrLower(StrReplace(StrReplace(StrReplace(Trim(hotkey), "~"), "$"), "*"))

    switch switchMethod {
      case "lShift":
        return normalizedHotkey = "lshift"
      case "rShift":
        return normalizedHotkey = "rshift"
      case "ctrlSpace":
        return normalizedHotkey = "^space" || normalizedHotkey = "ctrl & space"
      default:
        return false
    }
  }

  ; 读取输入法打开状态。
  ; 底层使用 ImmGetDefaultIMEWnd + WM_IME_CONTROL / IMC_GETOPENSTATUS。
  getOpenStatus(hwnd) {
    result := this.tryImeControl(hwnd, 0x5)
    return result.ok ? result.value : 0
  }

  ; 设置输入法打开状态。
  ; true 通常表示中文输入法打开，false 通常表示英文状态或关闭中文输入。
  setOpenStatus(status, hwnd) {
    try {
      imeHwnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
      DllCall("SendMessageTimeoutW", "ptr", imeHwnd, "uint", 0x283, "ptr", 0x6, "ptr", status ? 1 : 0, "uint", 0, "uint", this.checkTimeout, "ptr*", 0)
      return true
    } catch Error {
      return false
    }
  }

  ; 读取输入法转换码。
  ; 转换码用于区分中文、英文、全角、半角等状态，不同输入法返回值可能不同。
  getConversionMode(hwnd) {
    result := this.tryImeControl(hwnd, 0x1)
    return result.ok ? result.value : 0
  }

  ; 设置输入法转换码。
  ; 具体数值来自当前 profile 或用户配置的 cnConversionMode。
  setConversionMode(conversionMode, hwnd) {
    try {
      imeHwnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
      DllCall("SendMessageTimeoutW", "ptr", imeHwnd, "uint", 0x283, "ptr", 0x2, "ptr", conversionMode, "uint", 0, "uint", this.checkTimeout, "ptr*", 0)
      return true
    } catch Error {
      return false
    }
  }

  ; 获取真正拥有输入焦点的控件窗口。
  ; WinExist("A") 只能拿到前台顶层窗口；输入法状态通常要针对内部焦点控件读取。
  getFocusedWindow() {
    foregroundHwnd := WinExist("A")
    if !foregroundHwnd {
      return 0
    }

    guiThreadInfo := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
    NumPut("uint", guiThreadInfo.Size, guiThreadInfo)

    threadId := DllCall("GetWindowThreadProcessId", "ptr", foregroundHwnd, "ptr", 0, "uint")
    if !DllCall("GetGUIThreadInfo", "uint", threadId, "ptr", guiThreadInfo) {
      return foregroundHwnd
    }

    focusedHwnd := NumGet(guiThreadInfo, A_PtrSize = 8 ? 16 : 12, "ptr")
    return focusedHwnd ? focusedHwnd : foregroundHwnd
  }

  ; 统一执行 WM_IME_CONTROL 查询。
  ; SendMessageTimeoutW 的返回值能区分调用成功与否，比直接把 0 当状态更适合做切换前判断。
  tryImeControl(hwnd, controlCode) {
    try {
      controlValue := 0
      imeHwnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
      if !imeHwnd {
        return { ok: false, value: 0 }
      }

      sendResult := DllCall(
        "SendMessageTimeoutW",
        "ptr", imeHwnd,
        "uint", 0x283,
        "ptr", controlCode,
        "ptr", 0,
        "uint", 0,
        "uint", this.checkTimeout,
        "ptr*", &controlValue
      )
      return { ok: sendResult != 0, value: controlValue }
    } catch Error {
      return { ok: false, value: 0 }
    }
  }

  ; 从 config/ime.ini 读取所有 hotkey.* section。
  ; 只有 enabled=true、hotkey 有值、targetState 可识别的规则才会被加载。
  loadHotkeyRules() {
    hotkeyRules := []

    for sectionName in this.config.readSectionNames() {
      if (sectionName = "" || !this.startsWith(sectionName, "hotkey.")) {
        continue
      }

      if !this.config.readBool(sectionName, "enabled", true) {
        continue
      }

      hotkey := this.config.readText(sectionName, "hotkey")
      targetState := this.normalizeTargetState(this.config.readText(sectionName, "targetState"))
      passThrough := this.config.readBool(sectionName, "passThrough", false)
      switchMethod := this.normalizeSwitchMethod(this.config.readText(sectionName, "switchMethod", this.switchMethod))
      sendAfterSwitch := this.config.readText(sectionName, "sendAfterSwitch")
      scopeProcessNames := this.parseProcessNames(sectionName)

      if (hotkey = "" || targetState = "") {
        continue
      }

      hotkeyRules.Push(imeHotkeyRule(sectionName, hotkey, targetState, passThrough, switchMethod, sendAfterSwitch, scopeProcessNames))
    }

    return hotkeyRules
  }

  ; 从 config/ime.ini 读取固定的 appDefault.toEnglish 和 appDefault.toChinese。
  ; 目标状态由 section 名称决定，应用范围统一用 processNames 配置。
  loadAppDefaultRules() {
    appDefaultRules := []
    this.pushAppDefaultRule(appDefaultRules, "appDefault.toEnglish", "EN")
    this.pushAppDefaultRule(appDefaultRules, "appDefault.toChinese", "CN")
    return appDefaultRules
  }

  ; 读取并追加一组固定目标状态的应用默认规则。
  pushAppDefaultRule(appDefaultRules, sectionName, targetState) {
    if !this.config.readBool(sectionName, "enabled", true) {
      return
    }

    processNames := this.parseProcessNames(sectionName)
    if (processNames.Length = 0) {
      return
    }

    switchMethod := this.normalizeSwitchMethod(this.config.readText(sectionName, "switchMethod", this.switchMethod))
    appDefaultRules.Push(imeAppDefaultRule(sectionName, targetState, processNames, switchMethod))
  }

  ; 启动活动窗口监听轮询。
  ; InputTip 使用主循环检查进程名变化；这里用 SetTimer 保持本项目 manager 模式。
  startAppDefaultWatcher() {
    if (!this.appDefaultsEnabled || this.appDefaultRuleByProcessName.Count = 0) {
      return 0
    }

    SetTimer(this.checkAppDefaultCallback, this.appDefaultInterval)
    this.checkAppDefaultState()
    return 1
  }

  ; 检查当前活动窗口是否命中默认输入法状态规则。
  ; 仅在活动窗口进程变化时触发，避免同一应用内切换标题时重复切换。
  checkAppDefaultState(*) {
    if this.appDefaultChecking {
      return false
    }

    this.appDefaultChecking := true

    try {
      processName := this.getActiveProcessName()
      if (processName = "" || this.isSameProcessName(processName, this.lastAppDefaultProcessName)) {
        return false
      }

      if (this.appDefaultFocusDelay > 0) {
        Sleep(this.appDefaultFocusDelay)
      }

      processName := this.getActiveProcessName()
      if (processName = "" || this.isSameProcessName(processName, this.lastAppDefaultProcessName)) {
        return false
      }

      matchedRule := this.findMatchingAppDefaultRule(processName)
      this.lastAppDefaultProcessName := processName

      if !IsObject(matchedRule) {
        return false
      }

      if !this.canManageInputState() {
        return false
      }

      return this.switchToState(matchedRule.targetState, matchedRule)
    } catch Error as err {
      OutputDebug("keyon: 应用默认输入法状态切换失败：" err.Message)
      return false
    } finally {
      this.appDefaultChecking := false
    }
  }

  ; 读取当前活动窗口的进程名。
  ; 热键作用域和应用默认状态都统一基于进程名判断。
  getActiveProcessName() {
    activeHwnd := WinExist("A")
    if !activeHwnd {
      return ""
    }

    try {
      return WinGetProcessName(windowHelper.toWinId(activeHwnd))
    } catch Error {
      return ""
    }
  }

  ; 为应用默认状态规则建立进程名索引，避免轮询时反复遍历所有配置项。
  ; 如果同一进程同时出现在中英文列表里，保留先注册的规则，即 toEnglish 优先。
  buildAppDefaultRuleIndex() {
    appDefaultRuleByProcessName := Map()

    for currentRule in this.appDefaultRules {
      for currentProcessName in currentRule.processNames {
        normalizedProcessName := this.normalizeProcessName(currentProcessName)
        if (normalizedProcessName != "" && !appDefaultRuleByProcessName.Has(normalizedProcessName)) {
          appDefaultRuleByProcessName[normalizedProcessName] := currentRule
        }
      }
    }

    return appDefaultRuleByProcessName
  }

  ; 查找当前进程命中的应用默认状态规则。
  findMatchingAppDefaultRule(processName) {
    normalizedProcessName := this.normalizeProcessName(processName)
    if (normalizedProcessName = "" || !this.appDefaultRuleByProcessName.Has(normalizedProcessName)) {
      return ""
    }

    return this.appDefaultRuleByProcessName[normalizedProcessName]
  }

  ; 判断两个进程名是否一致；进程名按 Windows 习惯做大小写不敏感匹配。
  isSameProcessName(leftProcessName, rightProcessName) {
    return this.normalizeProcessName(leftProcessName) = this.normalizeProcessName(rightProcessName)
  }

  ; 统一进程名格式。
  ; Windows 进程名大小写不敏感，集中规整可以减少不同匹配入口的重复处理。
  normalizeProcessName(processName) {
    return StrLower(Trim(processName))
  }

  ; 判断单条输入法热键是否应在当前活动窗口生效。
  ; 未配置 processNames 时保持全局行为；配置后当前进程名命中任一项即生效。
  isHotkeyActiveForCurrentWindow(currentRule) {
    if !IsObject(currentRule) || !IsObject(currentRule.scopeProcessNames) || currentRule.scopeProcessNames.Length = 0 {
      return true
    }

    processName := this.getActiveProcessName()
    if (processName = "") {
      return false
    }

    return this.processNameMatchesAny(processName, currentRule.scopeProcessNames)
  }

  ; 解析进程名列表。
  ; 支持用 |、英文/中文逗号、分号分隔，供 hotkey.* 和 appDefault.* 复用。
  parseProcessNames(sectionName) {
    processNames := []
    multipleProcessNames := this.config.readText(sectionName, "processNames")

    normalizedListText := StrReplace(StrReplace(StrReplace(multipleProcessNames, "，", "|"), ",", "|"), ";", "|")
    for currentProcessName in StrSplit(normalizedListText, "|") {
      this.pushProcessName(processNames, currentProcessName)
    }

    return processNames
  }

  ; 向进程名列表追加单项，并按大小写不敏感方式去重。
  pushProcessName(processNames, processName) {
    normalizedProcessName := Trim(processName)
    if (normalizedProcessName = "" || this.processNameMatchesAny(normalizedProcessName, processNames)) {
      return
    }

    processNames.Push(normalizedProcessName)
  }

  ; 判断当前进程名是否命中配置列表。
  processNameMatchesAny(processName, processNames) {
    normalizedProcessName := this.normalizeProcessName(processName)
    if (normalizedProcessName = "") {
      return false
    }

    for currentProcessName in processNames {
      if (normalizedProcessName = this.normalizeProcessName(currentProcessName)) {
        return true
      }
    }

    return false
  }

  ; 在输入法切换逻辑执行后主动补发按键。
  ; 典型场景是拦截 Esc：先切到英文，再发送 {Esc}，避免透传 Esc 抢先改变焦点。
  sendAfterSwitch(currentRule) {
    if !IsObject(currentRule) || currentRule.sendAfterSwitch = "" {
      return
    }

    SendInput(currentRule.sendAfterSwitch)
  }

  ; 生成最终传给 AHK Hotkey() 的热键名称。
  ; 自动补 `$` 防止脚本模拟按键递归触发；passThrough=true 时补 `~` 保留原按键作用。
  buildHotkeyName(hotkey, passThrough) {
    hotkeyName := Trim(hotkey)

    ; Esc & a 这类自定义组合键必须保留 AHK 的“前缀键 & 触发键”格式。
    ; 普通热键才自动加 $；自定义组合键加 $ 可能导致注册失败或语义不清。
    if InStr(hotkeyName, " & ") {
      if (passThrough && SubStr(hotkeyName, 1, 1) != "~") {
        hotkeyName := "~" hotkeyName
      }

      return hotkeyName
    }

    ; $ 避免本脚本发送的按键再次触发同一个热键；~ 用于保留按键原本作用。
    if !InStr(hotkeyName, "$") {
      hotkeyName := "$" hotkeyName
    }

    if (passThrough && !InStr(hotkeyName, "~")) {
      hotkeyName := "~" hotkeyName
    }

    return hotkeyName
  }

  ; 统一目标状态写法。
  ; 允许用户在配置中写 CN/EN/TOGGLE，也兼容中文、英文等更直观的写法。
  normalizeTargetState(targetState) {
    targetState := StrUpper(Trim(targetState))

    switch targetState {
      case "CN", "CHINESE", "ZH", "中文":
        return "CN"
      case "EN", "ENGLISH", "英文":
        return "EN"
      case "TOGGLE", "SWITCH", "切换":
        return "TOGGLE"
      default:
        return ""
    }
  }

  ; 统一切换方式写法。
  ; 配置无效时回退到 dll，保证默认行为可预测。
  normalizeSwitchMethod(switchMethod) {
    switchMethod := StrLower(Trim(switchMethod))

    switch switchMethod {
      case "dll":
        return "dll"
      case "lshift", "leftshift":
        return "lShift"
      case "rshift", "rightshift":
        return "rShift"
      case "ctrlspace", "ctrl+space", "controlspace":
        return "ctrlSpace"
      default:
        return "dll"
    }
  }

  ; 根据输入法配置档返回默认中文转换码。
  ; 微软拼音默认 1025，微信输入法默认 1；用户可用 cnConversionMode 覆盖。
  getDefaultCnConversionMode() {
    switch StrLower(Trim(this.profile)) {
      case "microsoftpinyin", "ms-pinyin", "ms_pinyin":
        return 1025
      case "wechatinput", "wechat", "weixin":
        return 1
      default:
        return 1
    }
  }

  ; 判断字符串是否以指定前缀开头。
  ; 当前用于识别 config/ime.ini 中的 hotkey.* section。
  startsWith(value, prefix) {
    return SubStr(value, 1, StrLen(prefix)) = prefix
  }
}
