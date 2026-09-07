class diagnosticLogger {
  static dataDirectory := EnvGet("LOCALAPPDATA") "\keyon"
  static logDirectory := this.dataDirectory "\logs"
  static logPath := this.logDirectory "\keyon.log"
  static maxLogSize := 1024 * 1024
  static maxHistoryCount := 5
  static startedAt := A_TickCount

  static initialize() {
    this.write("INFO", "startup", "version=" A_AhkVersion " compiled=" A_IsCompiled " admin=" A_IsAdmin)
    OnError(ObjBindMethod(this, "handleError"))
    OnExit(ObjBindMethod(this, "handleExit"))
  }

  static markReady(hotkeyCount) {
    this.write("INFO", "ready", "hotkeys=" hotkeyCount)
  }

  static requestStop(reason := "user") {
    try {
      DirCreate(this.dataDirectory)
      stopPath := this.dataDirectory "\stop-requested"
      if FileExist(stopPath) {
        FileDelete(stopPath)
      }
      FileAppend(reason, stopPath, "UTF-8")
      this.write("INFO", "stop_requested", "reason=" reason)
    }
  }

  static handleError(errorValue, mode) {
    details := "mode=" this.sanitize(mode)
      . " type=" this.sanitize(Type(errorValue))
      . " message=" this.sanitize(errorValue.Message)
      . " what=" this.sanitize(errorValue.What)
      . " file=" this.sanitize(errorValue.File)
      . " line=" this.sanitize(errorValue.Line)
      . " stack=" this.sanitize(errorValue.Stack)
    this.write("ERROR", "unhandled_error", details)
    try TrayTip("Keyon 发生错误", "诊断信息已写入 " this.logPath, 5)
    return 1
  }

  static handleExit(exitReason, exitCode) {
    uptimeSeconds := Floor((A_TickCount - this.startedAt) / 1000)
    this.write("INFO", "exit", "reason=" this.sanitize(exitReason) " code=" exitCode " uptimeSeconds=" uptimeSeconds)
  }

  static write(level, eventName, details := "") {
    try {
      DirCreate(this.logDirectory)
      this.rotateIfNeeded()
      timestamp := FormatTime(, "yyyy-MM-dd'T'HH:mm:ss")
      line := timestamp "`tlevel=" level "`tevent=" eventName "`tpid=" DllCall("GetCurrentProcessId")
      if (details != "") {
        line .= "`t" details
      }
      FileAppend(line "`n", this.logPath, "UTF-8")
    }
  }

  static rotateIfNeeded() {
    if (!FileExist(this.logPath) || FileGetSize(this.logPath) < this.maxLogSize) {
      return
    }

    oldestPath := this.logPath "." this.maxHistoryCount
    if FileExist(oldestPath) {
      FileDelete(oldestPath)
    }

    Loop this.maxHistoryCount - 1 {
      sourceIndex := this.maxHistoryCount - A_Index
      sourcePath := this.logPath "." sourceIndex
      if FileExist(sourcePath) {
        FileMove(sourcePath, this.logPath "." (sourceIndex + 1), 1)
      }
    }
    FileMove(this.logPath, this.logPath ".1", 1)
  }

  static sanitize(value) {
    text := String(value)
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    return StrReplace(text, "`t", " ")
  }
}