; 单个输入法状态切换快捷键的内存结构。
; 只保存热键、目标状态和是否透传原按键，不直接执行切换。
class imeHotkeyRule {
  ; 初始化一条输入法快捷键规则。
  ; targetState 支持 CN、EN、TOGGLE；sendAfterSwitch 用于在切换后主动补发原按键。
  __New(name, hotkey, targetState, passThrough, switchMethod, sendAfterSwitch) {
    this.name := name
    this.hotkey := hotkey
    this.targetState := targetState
    this.passThrough := passThrough
    this.switchMethod := switchMethod
    this.sendAfterSwitch := sendAfterSwitch
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
    this.hotkeyRules := this.loadHotkeyRules()
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

    return registeredCount
  }

  ; 输入法快捷键触发入口。
  ; currentRule 会被继续传入，用于判断 passThrough、切换方式和切换后的补发按键。
  handleStateHotkey(currentRule, *) {
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

      if (hotkey = "" || targetState = "") {
        continue
      }

      hotkeyRules.Push(imeHotkeyRule(sectionName, hotkey, targetState, passThrough, switchMethod, sendAfterSwitch))
    }

    return hotkeyRules
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
