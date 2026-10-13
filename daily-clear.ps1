<#
  daily-clear.ps1 — 《明日方舟》端游 + MAA 每日清体力(单游戏仓库入口)

  .\daily-clear.ps1 -DryRun          # 只看今天会怎么跑，不碰任何程序
  .\daily-clear.ps1                  # 完整跑一轮
  .\daily-clear.ps1 -ShopDone        # 确认"活动商店已领空"→ 剩余理智改刷长草计划
  .\daily-clear.ps1 -ShopReset       # 撤销上面的领空标记(误点/活动又开新一批兑换)
  .\daily-clear.ps1 -Farm            # 本轮只刷目标材料缺口(config 里 ark.farmTargets 配的目标)
  .\daily-clear.ps1 -Stage SK-5      # 临时指定刷哪几关(逗号分隔，会拿 MAA 的关卡表校验)
  .\daily-clear.ps1 -Force           # 本轮忽略活动图的"每轮自证"结论，强行按活动图刷
  .\daily-clear.ps1 -SkipCleanup     # 跑完不关端游/MAA(自己接着玩)
  .\daily-clear.ps1 -NoElevate       # 禁止自动提权(只在看输出时用；真跑大概率连不上端游)
  计划任务每日按 config\settings.json 的 schedule.times 调用：daily-clear.ps1 -Tag auto
  权限：端游 + MAA 要管理员。非提权运行时脚本会弹一次 UAC 并以管理员身份重跑自己(-NoElevate 可禁止)。

  退出码：0=这一轮判定为完成；2=没完成(细节看 logs\ 里那一轮的日志和通知气泡)。

  —— 本文件现在是什么 ——
  只是命令行外壳：把 -ShopDone / -ShopReset 这些短名翻译成"给 ark 模块的哪道门"，剩下的整轮流程
  在 lib\modules.ps1 的 Invoke-GdDailyRound 里 —— 和另一款游戏的仓库、以及本地那份管两款的入口，
  跑的是同一套实现。这个仓库里只装了 ark-module.ps1，所以注册表天然只有一款，不用 -Games 参数。
  -Ack 这一道人工门已于 2026-10-12 退场：活动图改由每轮拿"活动最后一关"当探针自证(进得去就刷，
  被 MAA 修剪掉就当日改刷长草、下一轮自动切回)，参数先留着只为兼容还在敲它的旧脚本，敲下去只打日志。
#>
# 运行环境：PowerShell 7(pwsh)。本仓库只支持 7，不再为系统自带的 Windows PowerShell 5.1 留兼容退路。
[CmdletBinding()]
param(
    [ValidateSet('auto', 'manual')][string]$Tag = 'manual',
    [switch]$DryRun,
    # -Ack 现在是"只打日志的兼容位"：2026-10-12 起活动图改每轮机器自证，判定层不再读 ark-event-ack；
    # 参数留着只为还在敲它的旧脚本/计划任务，删它留到推仓那批和导出表自检一起动。
    [Alias('ConfirmEvent')][switch]$Ack,
    [Alias('MarkShopDone')][switch]$ShopDone,
    [switch]$ShopReset,
    [switch]$Farm,
    [switch]$SkipCleanup,
    [switch]$Force,
    [switch]$NoElevate,
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'lib\decisions.ps1')      # 门面：仓库里有哪些判定文件就点哪些
. (Join-Path $PSScriptRoot 'lib\modules.ps1')
. (Join-Path $PSScriptRoot 'lib\supervisor.ps1')   # 监督 agent(可整行删掉=这一轮没人监督，主流程不受影响)

Start-GdTranscript -Tag "daily-$Tag"
Write-GdLog "=== 方舟日常开始(tag=$Tag, dryRun=$DryRun)===" -Level STEP

# ---------- 内核接线(源码 tools\gdcore\*.cs，装载器与契约号在 lib\common.ps1 末尾那块) ----------
# 必须排在 Get-GdSettings 之前(内核化的七件里就有读配置那两件)；编不成一律静默回退 PS 原身，内核不是硬依赖。
$null = Add-GdCore
$coreT0 = Get-Date
$coreNote = Get-GdCoreStatus
if ($coreNote) { Write-GdLog $coreNote -Level WARN }
Write-GdLog (Get-GdCoreReadout)

# 先注册清单，再在本脚本顶层把这个工程真正要跑的那一路的业务库点进来
# (清单里那三项 Libs 就是这件事的名单；不能在函数里 dot-source，见 modules.ps1 的 Import-GdModules)。
[void](Import-GdModules)
foreach ($libPath in (Get-GdModuleLibPaths)) { . $libPath }

# 单游戏仓库里 Sync-GdEntryVerbs 什么都不做(注册表只有一款 → 不是合体工程)，
# 提示语保持判定层默认的干净短名 —— 也就是这个入口真能认的 -Ack / -ShopDone / -ShopReset。
Sync-GdEntryVerbs

# 没配置这件事由脚本自己用日志的格式说清楚就走(-TellAndExit)：裸 throw 到了顶层是一屏
# "Exception: C:\...\common.ps1:120 / Line | ..." 那种内部报错，双击的人只会以为程序坏了。
$S = Get-GdSettings -TellAndExit

# settings.runtime.coreOff：单个内核函数出 bug，改一行配置就把那一件退回 PS 原身(当日止血，不挡其余)
$null = Sync-GdCoreOff -Settings $S

$gates = @()
if ($Ack) { $gates += @{ Id = 'ark'; Verb = 'Ack' } }
if ($ShopDone) { $gates += @{ Id = 'ark'; Verb = 'ShopDone' } }
if ($ShopReset) { $gates += @{ Id = 'ark'; Verb = 'ShopReset' } }

# 汇总/气泡里用中文短名('方舟')而不是模块 id：这份入口历史上就是这个措辞，别在重构里顺手改掉。
$code = Invoke-GdDailyRound -S $S -ElevateScript (Join-Path $PSScriptRoot 'daily-clear.ps1') -BoundParams $PSBoundParameters -Gates $gates -Opt @{ Stage = $Stage; Farm = [bool]$Farm } -Force:$Force -DryRun:$DryRun -SkipCleanup:$SkipCleanup -NoElevate:$NoElevate -NameField ShortName -NoticeOwner '方舟' -Tag $Tag
Write-GdLog ('收尾 ' + (Get-GdCoreReadout -ElapsedSec ((Get-Date) - $coreT0).TotalSeconds))
exit $code
