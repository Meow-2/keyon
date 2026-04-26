# mine-key

`mine-key` 是一个基于 AutoHotkey v2 的 Windows 快捷键工具。当前已实现两类能力：应用窗口管理，以及输入法状态切换。

当前启用的快捷键以 `config/apps.ini`、`config/ime.ini`、`config/tools.ini` 和 `config/keymap.ini` 为准。修改配置后重新运行或重载 `mineKey.ahk`。

## 环境要求

- Windows 11
- PowerShell
- AutoHotkey v2

当前脚本按 Scoop 的 AutoHotkey v2 安装路径运行：

```ps1
& "$env:USERPROFILE\scoop\apps\autohotkey\current\v2\AutoHotkey64.exe"
```

## 快速开始

1. 打开应用快捷键配置：

```ps1
notepad .\config\apps.ini
```

2. 添加一个应用配置。下面示例用于测试记事本：

```ini
[notepad]
enabled=true
hotkey=#!n
winTitle=ahk_exe notepad.exe
matchMode=contains
target=notepad.exe
args=
workingDir=
processName=notepad.exe
wakeHotkey=
detectHidden=false
waitSeconds=3
runAsAdmin=false
```

3. 运行脚本：

```ps1
& "$env:USERPROFILE\scoop\apps\autohotkey\current\v2\AutoHotkey64.exe" .\mineKey.ahk
```

4. 按下示例快捷键 `Win + Alt + N`：

- 记事本未启动时：启动记事本并尝试获取焦点。
- 记事本已有窗口显示时：在记事本窗口之间切换。
- 记事本窗口最小化时：恢复窗口并获取焦点。

## 应用快捷键配置

应用配置位于 `config/apps.ini`。每个应用使用一个独立 section。

普通应用通常只需要最小配置：

```ini
[notepad]
hotkey=#!n
winTitle=ahk_exe notepad.exe
target=notepad.exe
```

完整配置格式如下：

```ini
[appName]
enabled=true
hotkey=#!n
winTitle=ahk_exe app.exe
matchMode=contains
target=app.exe
args=
workingDir=
processName=app.exe
wakeHotkey=
detectHidden=false
waitSeconds=3
runAsAdmin=false
```

字段含义：

- `[appName]`：配置块名称，只用于区分不同应用。可以写成 `notepad`、`vscode`、`browser` 等便于理解的名称。
- `enabled`：是否启用该配置。可选，省略时默认启用。可用值为 `true` 或 `false`。
- `hotkey`：触发该应用动作的快捷键。必填。AHK 热键语法中，`#` 表示 Win，`!` 表示 Alt，`^` 表示 Ctrl，`+` 表示 Shift，例如 `#!n` 表示 `Win + Alt + N`。
- `winTitle`：用来查找已有窗口的 AHK WinTitle 表达式。强烈建议填写，否则程序无法判断窗口是否已经存在，也无法进行窗口切换。常用写法有 `ahk_exe notepad.exe`、`ahk_class CabinetWClass`、窗口标题的一部分。
- `matchMode`：`winTitle` 的匹配方式。可选，省略时默认 `contains`。可用值为 `contains`、`exact`、`startsWith`、`regex`。
- `target`：应用不存在时要运行的启动命令。强烈建议填写，否则只能激活已有窗口，不能启动应用。可以是 exe、快捷方式、目录、URL、`shell:` 链接或 `ms-settings:` 链接。
- `args`：启动参数。可选，多数应用可以留空。适合给编辑器传入目录或文件路径。
- `workingDir`：启动应用时使用的工作目录。可选，多数应用可以留空。
- `processName`：后台进程名。可选，主要用于托盘应用或后台应用。当应用没有普通窗口但进程仍存在时，可配合 `wakeHotkey` 呼出窗口。
- `wakeHotkey`：应用自己的呼出快捷键。可选，主要用于微信、QQ 等托盘应用。例如 `^!w` 表示 `Ctrl + Alt + W`。
- `detectHidden`：是否额外查找隐藏窗口。可选，省略时默认 `false`。普通应用不建议开启，只有窗口被隐藏且普通查找找不到时再设为 `true`。
- `waitSeconds`：启动或呼出应用后等待窗口出现的秒数。可选，省略时默认 `3`。应用启动较慢时可以调大，例如 `5` 或 `8`。
- `runAsAdmin`：是否以管理员权限启动该应用。可选，省略时默认 `false`。由于 `mine-key.exe` 通常以管理员权限运行，`false` 会通过普通权限 Explorer 代理启动，避免把浏览器、编辑器、终端等应用也带成管理员进程；只有确实需要管理权限的目标才设为 `true`。

`matchMode` 详细说明：

|值 |含义 |
|---|---|
|`contains` |包含匹配，默认值。`winTitle=Code` 可以匹配标题中包含 `Code` 的窗口。 |
|`exact` |精确匹配。窗口标题必须和 `winTitle` 完全一致。 |
|`startsWith` |开头匹配。窗口标题必须以 `winTitle` 开头。 |
|`regex` |正则匹配。适合复杂标题，但需要自己保证表达式正确。 |

## 输入法状态切换配置

输入法配置位于 `config/ime.ini`。每个状态切换快捷键使用一个 `hotkey.` 开头的 section。

下面示例把 `CapsLock` 配置为切换到英文状态，并拦截 CapsLock 原本的大写锁定作用：

```ini
[general]
enabled=true
profile=microsoftPinyin
switchMethod=dll
checkTimeout=500

[hotkey.toEnglish]
enabled=true
hotkey=CapsLock
targetState=EN
passThrough=false
switchMethod=dll
```

下面示例把 `Esc` 配置为“先切到英文，再发送 Esc”，用于保留 Esc 原本关闭弹窗、退出输入框等作用，同时避免透传 Esc 抢先改变焦点：

```ini
[hotkey.toEnglish]
enabled=true
hotkey=Esc
targetState=EN
passThrough=false
switchMethod=dll
sendAfterSwitch={Esc}
```

下面示例把右 Shift 配置为切换到中文状态，并保留右 Shift 原本作用：

```ini
[general]
enabled=true
profile=wechatInput
switchMethod=dll
checkTimeout=500

[hotkey.toChinese]
enabled=true
hotkey=RShift
targetState=CN
passThrough=true
switchMethod=dll
```

字段含义：

- `profile`：输入法配置档，当前支持 `microsoftPinyin` 和 `wechatInput`。
- `[general]` 下的 `switchMethod`：默认切换方式，支持 `dll`、`lShift`、`rShift`、`ctrlSpace`。
- `[hotkey.*]` 下的 `switchMethod`：可选；覆盖单个热键的切换方式，省略时使用 `[general]` 的默认值。
- `checkTimeout`：读取输入法状态的超时时间，单位毫秒。
- `cnConversionMode`：可选；覆盖当前配置档切换到中文时使用的转换码。
- `hotkey`：触发切换的 AHK 热键。
- `targetState`：目标状态，支持 `CN`、`EN`、`TOGGLE`。
- `passThrough`：是否保留按键原本作用。`true` 会让按键继续传递给系统或当前应用，`false` 会拦截该按键。
- `sendAfterSwitch`：切换逻辑执行后主动发送的按键。可选，使用 AHK `Send` 语法，例如 `{Esc}`。需要先切输入法再保留原按键作用时，优先使用 `passThrough=false` 加 `sendAfterSwitch`。

`Esc + 字母` 这类组合键使用 AHK 自定义组合键写法，例如：

```ini
[hotkey.escA]
enabled=true
hotkey=Esc & a
targetState=EN
passThrough=false
switchMethod=dll
```

注意：`Esc & a` 会把 `Esc` 变成前缀键。若仍需要单独按 `Esc` 生效，应另配一条 `hotkey=Esc` 规则，或把 `passThrough` 设置为符合当前需求的值。

切换逻辑会先检测当前输入法状态。如果当前已经是目标状态，不会重复切换。

如果 `passThrough=true` 且触发键本身就是 `lShift`、`rShift` 或 `ctrlSpace` 对应的切换键，程序会先等待原按键生效，避免额外模拟同一个键造成二次切换。

## 工具类快捷键配置

工具类快捷键配置位于 `config/tools.ini`。当前支持“查看当前窗口信息和输入法状态”以及通用窗口管理。

启用示例：

```ini
[windowInfo]
enabled=true
hotkey=#!i
copyToClipboard=true
```

字段含义：

- `enabled`：是否启用该工具快捷键。可选，建议显式写出。
- `hotkey`：触发信息查看的 AHK 热键，例如 `#!i` 表示 `Win + Alt + I`。
- `copyToClipboard`：是否把 `winTitle`、`target`、`processName` 三行推荐配置复制到剪贴板。可选，省略时默认 `true`。

触发后会显示：

- 当前活动窗口标题、进程名、进程 ID、窗口类名、窗口句柄。
- 可直接参考的推荐配置：`winTitle=ahk_exe ...`、`target=...`、`processName=...`。
- 可手动复制的备用 `winTitle` 写法：`winTitle=ahk_class ...` 和 `winTitle=ahk_id ...`。
- 启用 `copyToClipboard` 时，会自动复制 `winTitle=...`、`target=...`、`processName=...` 三行，方便直接粘贴到 `apps.ini`。
- 当前窗口位置、尺寸和最大化/最小化状态。
- 下方测试输入框的输入法状态：`CN` 或 `EN`。
- 下方测试输入框的输入焦点句柄、打开状态码、转换码和键盘布局；切换输入法时会实时刷新。

这个功能主要用于配置 `apps.ini` 和排查输入法状态识别问题。

信息窗口上方使用只读文本框展示，支持鼠标选择局部文本并复制；下方输入框默认获得焦点，用于测试和观察输入法状态变化。

窗口管理配置示例：

```ini
[windowControl]
enabled=true
closeHotkey=#q
nextHotkey=#j
previousHotkey=#k
switchMode=managed
waitSeconds=1
previewSeconds=0.6
previewMaxItems=8
previewFontSize=16
previewWidth=760
```

字段含义：

- `closeHotkey`：关闭当前活动窗口，默认配置为 `#q`，即 `Win + Q`。
- `nextHotkey`：切换到下一个可管理窗口，默认配置为 `#j`，即 `Win + J`。
- `previousHotkey`：切换到上一个可管理窗口，默认配置为 `#k`，即 `Win + K`。
- `switchMode`：窗口切换方式，支持 `managed` 和 `system`。`managed` 使用项目自己的窗口列表和居中预览；`system` 使用 Windows 原生 `Alt+Tab` / `Alt+Shift+Tab`。
- `waitSeconds`：切换后等待目标窗口激活的秒数，省略时默认 `1`。
- `previewSeconds`：窗口候选列表提示显示的秒数，省略时默认 `0.6`。仅非 Win 组合键触发的 `managed` 切换使用该超时；设为 `0` 可关闭提示。
- `previewMaxItems`：候选列表最多显示的窗口数量，省略时默认 `8`。
- `previewFontSize`：候选列表字体大小，省略时默认 `16`。
- `previewWidth`：候选列表窗口宽度，省略时默认 `760`。

`switchMode=managed` 时，窗口切换会跳过桌面、任务栏、空标题窗口、隐藏窗口、工具窗口和 `crashpad` 后台辅助窗口，并在当前屏幕中央显示候选窗口列表。如果 `nextHotkey` / `previousHotkey` 使用 Win 组合键，例如 `#j` / `#k`，则按住 Win 期间预览会持续显示，松开 Win 后立即消失，中间可以继续按 `J` / `K` 循环切换。`switchMode=system` 时，窗口顺序和候选界面完全交给 Windows 系统处理，预览相关配置不生效；如果 `nextHotkey` / `previousHotkey` 使用 Win 组合键，例如 `#j` / `#k`，可以按住 Win 不放，连续按 `J` / `K` 在系统切换候选中循环，松开 Win 后确认目标窗口。

## 按键映射配置

按键映射配置位于 `config/keymap.ini`。

示例：

```ini
[keyMap.esc1]
enabled=true
hotkey=Esc & 1
sendKeys=#1
```

字段含义：

- `hotkey`：触发映射的 AHK 热键，支持 `Esc & 1` 这类前缀键组合。
- `sendKeys`：触发后发送的目标按键串，使用 AHK `Send` 语法，例如 `#1`、`#0`、`#Enter`。

## 语法检查

修改脚本后，可以先运行静态检查：

```ps1
& "$env:USERPROFILE\scoop\apps\autohotkey\current\v2\AutoHotkey64.exe" /ErrorStdOut .\mineKey.ahk --check
```

该命令只加载脚本并立即退出，用于确认入口文件和依赖模块可被 AutoHotkey v2 正常解析。

## 构建与开机启动

构建脚本来自 `AutoKeyMap` 的同类脚本，并已适配为 `mine-key`：

```ps1
.\compile.bat
```

`compile.bat` 会请求管理员权限，然后调用 `scripts\compile.ps1`。编译流程：

1. 使用当前用户目录下的 Scoop AutoHotkey 路径：`%USERPROFILE%\scoop\apps\autohotkey\current\Compiler\Ahk2Exe.exe` 和 `%USERPROFILE%\scoop\apps\autohotkey\current\v2\AutoHotkey64.exe`。
2. 停止正在运行的 `mine-key.exe` 或 `mineKey.exe`。
3. 将 `mineKey.ahk` 编译为 `mine-key.exe`。
4. 编译成功后重新启动 `mine-key.exe`。

编译成功后，可以添加开机启动任务：

```ps1
.\scripts\enableAutoStartup.bat
```

该脚本会请求管理员权限，创建计划任务 `\mine-key\mine-key`，在用户登录时以 `HighestAvailable` 权限运行 `mine-key.exe`。

移除开机启动任务：

```ps1
.\scripts\disableAutoStartup.bat
```

`disableAutoStartup.bat` 同样会在需要时请求管理员权限。注意：`enableAutoStartup.bat` 依赖已存在的 `mine-key.exe`，因此应先运行 `compile.bat`。

## 注册表片段

`registry/` 目录保存可选的注册表配置文件，程序运行时不会自动导入。

- `registry/exchangeEscCapsLock.reg`：系统级交换 `Esc` 和 `CapsLock`。该文件写入 `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Keyboard Layout`，导入需要管理员权限，通常需要注销或重启后生效。
- `registry/xiaoHe.reg`：为当前用户配置微软拼音小鹤双拼。该文件写入 `HKEY_CURRENT_USER\Software\Microsoft\InputMethod\Settings\CHS`。

导入前建议先确认文件内容，并备份相关注册表项。需要回滚时，应删除或恢复对应注册表值，而不是重新运行 `mine-key`。

## 当前限制

- 默认配置没有启用任何真实应用。
- 托盘应用、虚拟桌面窗口和特殊 UWP 窗口可能需要额外的 `processName`、`wakeHotkey` 或匹配规则。
- 输入法功能当前支持按键触发的状态切换；按活动窗口自动切换输入法状态尚未实现。
- 不同输入法对状态码和切换码的支持存在差异。如果 `dll` 不稳定，可尝试 `lShift`、`rShift` 或 `ctrlSpace`。
- 工具类快捷键默认未启用，需要在 `config/tools.ini` 中手动取消注释或新增配置。

## 参考项目

本项目参考了以下开源项目的设计思路，并按 `mine-key` 的结构、命名和中文注释规范重新实现：

- [MyKeymap](https://github.com/xianyukang/MyKeymap)：参考应用启动、窗口激活和同应用窗口切换思路。
- [InputTip](https://github.com/abgox/InputTip)：参考输入法状态检测、状态切换和输入法兼容思路。

## 规格文档

功能规格和后续计划记录在 `prompt/mine-key.md`。修改功能前先更新该文档，再同步修改代码，确保行为可复现。
