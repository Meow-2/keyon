; 单个按键映射规则。
; 只保存触发热键和目标发送内容，不直接执行业务逻辑。
class keyMapRule {
  __New(name, hotkey, sendKeys) {
    this.name := name
    this.hotkey := hotkey
    this.sendKeys := sendKeys
  }
}

; 按键映射管理器。
; 负责读取 config/keymap.ini 中的 keyMap.* 配置，并把热键发送成目标按键序列。
class keyMapManager {
  __New(configPath) {
    this.config := configReader(configPath)
    this.keyMapRules := this.loadKeyMapRules()
  }

  ; 注册所有启用的按键映射。
  registerHotkeys() {
    registeredCount := 0

    for currentRule in this.keyMapRules {
      try {
        Hotkey(windowHelper.buildHookHotkeyName(currentRule.hotkey), ObjBindMethod(this, "handleKeyMapHotkey", currentRule), "On")
        registeredCount += 1
      } catch Error as err {
        MsgBox("按键映射注册失败：" currentRule.name "`n" err.Message, "mine-key")
      }
    }

    return registeredCount
  }

  ; 按键映射入口。
  ; 当前仅负责发送配置里的目标按键串。
  handleKeyMapHotkey(currentRule, *) {
    if (currentRule.sendKeys = "") {
      return false
    }

    SendInput(currentRule.sendKeys)
    return true
  }

  ; 从 keymap.ini 读取 keyMap.* section。
  loadKeyMapRules() {
    keyMapRules := []

    for sectionName in this.config.readSectionNames() {
      if (sectionName = "" || !this.startsWith(sectionName, "keyMap.")) {
        continue
      }

      if !this.config.readBool(sectionName, "enabled", true) {
        continue
      }

      hotkey := this.config.readText(sectionName, "hotkey")
      sendKeys := this.config.readText(sectionName, "sendKeys")
      if (hotkey = "" || sendKeys = "") {
        continue
      }

      keyMapRules.Push(keyMapRule(sectionName, hotkey, sendKeys))
    }

    return keyMapRules
  }

  ; 判断字符串是否以指定前缀开头。
  startsWith(value, prefix) {
    return SubStr(value, 1, StrLen(prefix)) = prefix
  }
}
