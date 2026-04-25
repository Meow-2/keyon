; INI 配置读取工具。
; 统一处理文本、布尔值和数字字段，避免各个 manager 重复维护相同的解析逻辑。
class configReader {
  __New(configPath) {
    this.configPath := configPath
  }

  ; 读取 INI 文本字段。
  ; 缺少配置或读取失败时返回默认值，避免单个字段错误中断主脚本。
  readText(sectionName, keyName, defaultValue := "") {
    try {
      return Trim(IniRead(this.configPath, sectionName, keyName, defaultValue))
    } catch Error {
      return defaultValue
    }
  }

  ; 读取 INI 布尔字段。
  ; 支持 1/true/yes/on 作为 true，其余值按 false 处理。
  readBool(sectionName, keyName, defaultValue := false) {
    value := StrLower(this.readText(sectionName, keyName, defaultValue ? "true" : "false"))
    return value = "1" || value = "true" || value = "yes" || value = "on"
  }

  ; 读取 INI 数字字段。
  ; 空值或读取失败时返回默认值；AHK 的 + 0 用于把字符串转换为数字。
  readNumber(sectionName, keyName, defaultValue := 0) {
    value := this.readText(sectionName, keyName, "")
    if (value = "") {
      return defaultValue
    }

    return value + 0
  }
}
