#Requires AutoHotkey v2.0
#SingleInstance Force

#Include lib\configReader.ahk
#Include lib\windowHelper.ahk
#Include lib\appWindowManager.ahk
#Include lib\imeManager.ahk
#Include lib\infoManager.ahk
#Include lib\keyMapManager.ahk
#Include lib\windowControlManager.ahk

SetWorkingDir(A_ScriptDir)
SetTitleMatchMode(2)
SetWinDelay(0)
Persistent(true)

configPath := A_ScriptDir "\config\apps.ini"
manager := appWindowManager(configPath)
imeConfigPath := A_ScriptDir "\config\ime.ini"
inputMethodManager := imeManager(imeConfigPath)
winToolsConfigPath := A_ScriptDir "\config\wintools.ini"
currentInfoManager := infoManager(winToolsConfigPath, inputMethodManager)
keyMapConfigPath := A_ScriptDir "\config\keymap.ini"
currentKeyMapManager := keyMapManager(keyMapConfigPath)
currentWindowControlManager := windowControlManager(winToolsConfigPath)

if (A_Args.Length && A_Args[1] = "--check") {
  ExitApp(0)
}

registeredCount := manager.registerHotkeys()
registeredImeCount := inputMethodManager.registerHotkeys()
registeredInfoCount := currentInfoManager.registerHotkeys()
registeredKeyMapCount := currentKeyMapManager.registerHotkeys()
registeredWindowControlCount := currentWindowControlManager.registerHotkeys()

if (registeredCount = 0 && registeredImeCount = 0 && registeredInfoCount = 0 && registeredKeyMapCount = 0 && registeredWindowControlCount = 0) {
  ; 没有配置有效快捷键时仍保持脚本运行，方便用户编辑配置后手动重载。
  OutputDebug("keyon: 没有启用任何快捷键。")
}
