# mine-key 工程规格

## 文档目的

本文件用于记录 `mine-key` AHK 工程的真实需求、实现约束和复现步骤。后续功能确认后，应先更新本文档，再同步修改程序，保证文档与代码一致。

## 已确认信息

- 项目名称：`mine-key`。
- 规格文件：`prompt/mine-key.md`。
- 入口文件：`mineKey.ahk`。
- 运行环境：Windows 11。
- 默认终端：PowerShell。
- 脚本版本：AutoHotkey v2，本次实现已在入口文件中声明 `#Requires AutoHotkey v2.0`。
- 参考来源：MyKeymap 开源项目；应用窗口管理功能参考其 `ActivateOrRun`、`ActivateWindow`、`LoopRelatedWindows` 的设计思路，但本项目按自身规范重新实现，不直接照搬代码风格。

## 待确认内容

以下内容尚未确定，后续按实际需求补充：

- 快捷键清单。
- 快捷键对应的应用、路径、进程名或窗口匹配规则。
- 需要特殊呼出热键的后台应用，例如托盘应用。
- 真实启用的输入法状态切换快捷键。
- 真实启用的窗口与输入法信息查看快捷键。
- 是否需要按活动窗口自动切换输入法状态。

## 快捷键打开应用

已确认目标：用快捷键管理应用的启动、呼出和同应用窗口切换。每个应用后续通过配置绑定一个快捷键。

快捷键触发时按以下状态执行：

| 应用状态 | 行为 | 焦点要求 |
| --- | --- | --- |
| 应用未启动 | 启动应用 | 启动后尽量激活匹配窗口 |
| 应用已启动，且有窗口显示在桌面上 | 在该应用的可见窗口之间切换 | 切换后的窗口必须获取焦点 |
| 应用已启动，但没有窗口显示在桌面上 | 恢复、显示或呼出该应用窗口 | 呼出后的窗口必须获取焦点 |

当前实现将“显示在桌面上”定义为：窗口可被 AHK 枚举、标题不为空、具有可见样式、且不是最小化状态。被其他窗口遮挡但未最小化的窗口仍视为显示在桌面上。

如果某些应用只驻留后台或托盘，普通窗口枚举可能无法呼出；这类应用后续可在配置中补充 `processName` 和 `wakeHotkey`。

## 输入法状态管理

已确认目标：允许检测当前输入法状态，并在需要时自动切换到指定状态。当前实现先支持“按下某个可配置快捷键后，切换到某个目标状态”。

参考来源：`InputTip/` 是本仓库内的开源参考项目；输入法功能参考其状态码、切换码、通用模式和状态切换快捷键思路，但本项目按自身规范重新实现。

当前支持的输入法配置档：

- `microsoftPinyin`：微软拼音。默认使用通用状态检测，切换到中文时的转换码默认值为 `1025`。
- `wechatInput`：微信输入法。默认使用通用状态检测，切换到中文时的转换码默认值为 `1`。

当前支持的目标状态：

- `CN`：中文状态。
- `EN`：英文状态。
- `TOGGLE`：在中文和英文之间切换。

当前支持的切换方式：

- `dll`：通过 Windows IMM 接口设置输入法打开状态和转换码。
- `lShift`：检测当前状态后，必要时模拟左 Shift。
- `rShift`：检测当前状态后，必要时模拟右 Shift。
- `ctrlSpace`：检测当前状态后，必要时模拟 Ctrl + Space。

状态切换快捷键通过 `config/ime.ini` 配置。每个快捷键可配置 `passThrough`：为 `true` 时，按键保留原本作用；为 `false` 时，按键只用于切换输入法状态。

每个快捷键可配置 `sendAfterSwitch`：切换逻辑执行后再主动发送指定按键，值使用 AHK `Send` 语法。典型用法是 `hotkey=Esc`、`passThrough=false`、`sendAfterSwitch={Esc}`，表示先切到英文，再发送一次 `Esc`。

如果 `passThrough=true` 且触发键本身就是当前切换方式使用的按键，程序应先等待原按键生效，避免额外模拟同一按键造成二次切换。

## 信息查看

已确认目标：允许用户通过一个可配置快捷键查看当前活动窗口信息和输入法状态。

当前查看内容：

- 活动窗口标题、进程名、进程 ID、窗口类名、窗口句柄。
- 可用于 `apps.ini` 的推荐配置：`winTitle=ahk_exe ...`、`target=...`、`processName=...`。
- 可用于 `apps.ini` 的备用 `winTitle` 写法：`winTitle=ahk_class ...`、`winTitle=ahk_id ...`。
- 活动窗口位置和尺寸。
- 下方测试输入框的输入法状态：`CN` 或 `EN`。
- 下方测试输入框的输入焦点句柄、输入法打开状态码、转换码和键盘布局；切换输入法时应实时刷新。

信息查看快捷键通过 `config/tools.ini` 配置，当前实际启用状态以该文件内容为准。

信息窗口上方应使用可选中文本的只读控件展示，允许用户手动选择并复制局部内容；下方应提供默认聚焦的输入框，用于实时测试输入法状态。

## 通用窗口管理

已确认目标：允许通过工具类快捷键管理当前窗口和全局窗口切换。

当前默认配置：

| 快捷键 | 行为 |
| --- | --- |
| `Win + Q` | 关闭当前活动窗口 |
| `Win + J` | 切换到下一个可管理窗口 |
| `Win + K` | 切换到上一个可管理窗口 |

窗口切换应允许选择两种模式：`managed` 使用项目自己的窗口列表和预览，并跳过桌面、任务栏、空标题窗口、隐藏窗口、工具窗口和 `crashpad` 后台辅助窗口；`system` 使用系统 `Alt+Tab` / `Alt+Shift+Tab`。当 `system` 模式由 Win 组合键触发时，应支持按住 Win 不放并连续按前后切换键循环候选窗口，松开 Win 后确认目标窗口。

## 目录结构

当前结构：

```text
.
├── mineKey.ahk              # AHK v2 入口脚本
├── compile.bat              # 构建入口，负责提权后调用 scripts/compile.ps1
├── config/
│   ├── apps.ini             # 应用快捷键配置
│   ├── ime.ini              # 输入法状态切换配置
│   └── tools.ini            # 工具类快捷键配置
├── lib/
│   ├── configReader.ahk     # INI 配置读取工具
│   ├── windowHelper.ahk     # 跨模块复用的窗口基础工具
│   ├── appWindowManager.ahk # 应用启动、呼出、窗口切换和焦点管理
│   ├── imeManager.ahk       # 输入法状态检测与切换
│   ├── infoManager.ahk      # 当前窗口与输入法信息查看
│   └── windowControlManager.ahk # 通用窗口关闭和前后切换
├── scripts/
│   ├── compile.ps1          # 编译 mineKey.ahk 为 mine-key.exe
│   ├── enableAutoStartup.bat # 添加开机计划任务
│   └── disableAutoStartup.bat # 删除开机计划任务
├── registry/
│   ├── exchangeEscCapsLock.reg # 系统级交换 Esc 与 CapsLock
│   └── xiaoHe.reg              # 当前用户的微软拼音小鹤双拼配置
└── prompt/
    └── mine-key.md          # 本规格文件
```

## 运行方式

PowerShell 中运行：

```powershell
& "$env:USERPROFILE\scoop\apps\autohotkey\current\v2\AutoHotkey64.exe" .\mineKey.ahk
```

如果系统已把 `.ahk` 文件关联到 AutoHotkey v2，也可以直接双击 `mineKey.ahk`。

静态语法检查：

```powershell
& "$env:USERPROFILE\scoop\apps\autohotkey\current\v2\AutoHotkey64.exe" /ErrorStdOut .\mineKey.ahk --check
```

`--check` 只加载脚本并立即退出，用于验证语法和依赖文件是否可加载。

## 构建与开机启动

已确认目标：复用上级目录 `AutoKeyMap` 中的构建和开机任务脚本思路，并适配为 `mine-key`。

当前脚本：

- `compile.bat`：构建入口，请求管理员权限后调用 `scripts/compile.ps1`。
- `scripts/compile.ps1`：使用当前用户目录下的 Scoop AutoHotkey v2 编译器路径，停止旧进程，编译 `mineKey.ahk` 为 `mine-key.exe`，并在成功后重启。
- `scripts/enableAutoStartup.bat`：请求管理员权限，生成计划任务 XML，并创建计划任务 `\mine-key\mine-key`。
- `scripts/disableAutoStartup.bat`：请求管理员权限，删除计划任务 `\mine-key\mine-key`。

构建命令：

```powershell
.\compile.bat
```

添加开机启动：

```powershell
.\scripts\enableAutoStartup.bat
```

移除开机启动：

```powershell
.\scripts\disableAutoStartup.bat
```

`enableAutoStartup.bat` 依赖 `mine-key.exe` 已存在，因此应先执行构建。开机任务使用 `HighestAvailable`，所以添加和移除任务时需要管理员权限。

## 注册表片段

已确认目标：把上级参考项目中的注册表片段纳入本项目，作为可选手动配置，不由 `mine-key` 自动导入。

当前文件：

- `registry/exchangeEscCapsLock.reg`：通过 `Keyboard Layout` 的 `Scancode Map` 交换 `Esc` 和 `CapsLock`，写入 `HKLM`，需要管理员权限，通常需要注销或重启后生效。
- `registry/xiaoHe.reg`：配置当前用户的微软拼音小鹤双拼，写入 `HKCU\Software\Microsoft\InputMethod\Settings\CHS`。

这些文件只负责系统或输入法基础设置；快捷键行为仍以 `config/ime.ini`、`config/apps.ini` 和 `config/tools.ini` 为准。

## 配置文件

应用快捷键配置位于 `config/apps.ini`。当前实际启用的应用快捷键以该文件内容为准，文档只记录字段含义和行为约束。

后续每个应用使用一个 INI section：

```ini
[appName]
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

字段说明：

- `enabled`：是否启用该应用配置。
- `hotkey`：AHK 热键语法；`#` 是 Win，`!` 是 Alt，`^` 是 Ctrl，`+` 是 Shift。
- `winTitle`：AHK 窗口匹配表达式，用于查找和聚焦窗口。
- `matchMode`：`winTitle` 的匹配方式，支持 `contains`、`exact`、`startsWith`、`regex`，省略时默认 `contains`。
- `target`：应用启动命令、可执行文件、快捷方式、目录或 URI。
- `processName`：可选；用于判断后台进程是否已存在。
- `wakeHotkey`：可选；用于呼出托盘或后台应用。
- `detectHidden`：是否额外枚举隐藏窗口。
- `waitSeconds`：启动或呼出后等待窗口出现的秒数。
- `runAsAdmin`：是否以管理员权限启动目标应用，省略时默认 `false`；`false` 应尽量通过普通权限 Explorer 代理启动，避免管理员权限的 `mine-key.exe` 把子进程也带成管理员。

输入法状态切换配置位于 `config/ime.ini`。当前实际启用状态以该文件内容为准。

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
sendAfterSwitch=
```

字段说明：

- `profile`：输入法配置档，当前支持 `microsoftPinyin` 和 `wechatInput`。
- `[general]` 下的 `switchMethod`：默认切换方式，支持 `dll`、`lShift`、`rShift`、`ctrlSpace`。
- `[hotkey.*]` 下的 `switchMethod`：可选；覆盖单个热键的切换方式，省略时使用 `[general]` 的默认值。
- `checkTimeout`：读取输入法状态的超时时间，单位毫秒。
- `cnConversionMode`：可选；覆盖当前配置档切换到中文时使用的转换码。
- `targetState`：快捷键触发后的目标状态，支持 `CN`、`EN`、`TOGGLE`。
- `passThrough`：是否让快捷键在触发切换后保留按键原本作用。
- `sendAfterSwitch`：切换逻辑执行后主动发送的按键；适合需要先切输入法再保留原按键作用的场景，例如 `{Esc}`。

AHK 自定义组合键使用 `前缀键 & 触发键` 格式，例如 `hotkey=Esc & a`。输入法热键注册逻辑应保留该格式，不自动添加 `$` 前缀。

工具类快捷键配置位于 `config/tools.ini`。当前支持窗口与输入法信息查看：

```ini
[windowInfo]
enabled=true
hotkey=#!i
copyToClipboard=true
```

字段说明：

- `enabled`：是否启用该工具快捷键。
- `hotkey`：触发信息查看的 AHK 热键。
- `copyToClipboard`：是否在弹窗显示时把 `winTitle`、`target`、`processName` 三行推荐配置复制到剪贴板。

通用窗口管理配置同样位于 `config/tools.ini`：

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

字段说明：

- `closeHotkey`：关闭当前活动窗口。
- `nextHotkey`：切换到下一个可管理窗口。
- `previousHotkey`：切换到上一个可管理窗口。
- `switchMode`：窗口切换方式，支持 `managed` 和 `system`。
- `waitSeconds`：等待目标窗口激活的秒数。
- `previewSeconds`：窗口候选列表提示显示的秒数，省略时默认 `0.6`，设为 `0` 可关闭提示。
- `previewMaxItems`：候选列表最多显示的窗口数量。
- `previewFontSize`：候选列表字体大小。
- `previewWidth`：候选列表窗口宽度。

## 验收标准

- `mineKey.ahk --check` 可以正常退出，表示脚本语法和引用文件可加载。
- 未配置有效应用时，脚本不应报错。
- 未配置有效输入法快捷键时，脚本不应报错。
- 未配置有效工具快捷键时，脚本不应报错。
- 配置有效应用后，按下对应快捷键应按本文档状态表执行。
- 启动、呼出、切换窗口三条路径最终都应尝试激活目标窗口并获取焦点。
- 配置有效输入法快捷键后，按下该键应先检测当前状态；如果当前状态不同，再切换到目标状态。
- 配置有效信息查看快捷键后，按下该键应显示当前窗口信息和输入法状态。
- 配置有效窗口管理快捷键后，关闭、上一个窗口、下一个窗口应对普通活动窗口生效。
- 行为变化必须先更新本文档，再修改代码。

## 实现原则

- 只改动完成任务所需的部分。
- 优先复用 AutoHotkey 内置能力、成熟 Windows API 调用和已有项目代码。
- 避免重复造轮子；公共逻辑确认稳定后再抽取复用。
- 项目代码标识符使用小驼峰命名。
- 代码注释使用中文，说明原因、边界条件和非显而易见的实现细节。
