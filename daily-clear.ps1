<#
  daily-clear.ps1 — 《明日方舟》端游 + MAA 每日清体力(单游戏仓库入口)

  .\daily-clear.ps1 -DryRun          # 只看今天会怎么跑，不碰任何程序
  .\daily-clear.ps1                  # 完整跑一轮
  .\daily-clear.ps1 -Ack             # 确认"新活动的图我自己手动打过了"→ 之后每天自动刷活动关卡
  .\daily-clear.ps1 -ShopDone        # 确认"活动商店已领空"→ 剩余理智改刷长草计划
  .\daily-clear.ps1 -ShopReset       # 撤销上面的领空标记(误点/活动又开新一批兑换)
  .\daily-clear.ps1 -Farm            # 本轮只刷目标材料缺口(config 里 ark.farmTargets 配的目标)
  .\daily-clear.ps1 -Stage SK-5      # 临时指定刷哪几关(逗号分隔，会拿 MAA 的关卡表校验)
  .\daily-clear.ps1 -SkipCleanup     # 跑完不关端游/MAA(自己接着玩)
  .\daily-clear.ps1 -NoElevate       # 禁止自动提权(只在看输出时用；真跑大概率连不上端游)
  计划任务每日按 config\settings.json 的 schedule.times 调用：daily-clear.ps1 -Tag auto
  权限：端游 + MAA 要管理员。非提权运行时脚本会弹一次 UAC 并以管理员身份重跑自己(-NoElevate 可禁止)。

  退出码：0=这一轮判定为完成；2=没完成(细节看 logs\ 里那一轮的日志和通知气泡)。

  —— 本文件现在是什么 ——
  只是命令行外壳：把 -Ack / -ShopDone 这些短名翻译成"给 ark 模块的哪道门"，剩下的整轮流程
  在 lib\modules.ps1 的 Invoke-GdDailyRound 里 —— 和另一款游戏的仓库、以及本地那份管两款的入口，
  跑的是同一套实现。这个仓库里只装了 ark-module.ps1，所以注册表天然只有一款，不用 -Games 参数。
#>
# 双引擎兼容：Windows PowerShell 5.1(系统自带) 与 PowerShell 7 都要能跑，别再加 #Requires 版本门把访客挡在门外。
[CmdletBinding()]
param(
    [ValidateSet('auto', 'manual')][string]$Tag = 'manual',
    [switch]$DryRun,
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

$gates = @()
if ($Ack) { $gates += @{ Id = 'ark'; Verb = 'Ack' } }
if ($ShopDone) { $gates += @{ Id = 'ark'; Verb = 'ShopDone' } }
if ($ShopReset) { $gates += @{ Id = 'ark'; Verb = 'ShopReset' } }

# 汇总/气泡里用中文短名('方舟')而不是模块 id：这份入口历史上就是这个措辞，别在重构里顺手改掉。
$code = Invoke-GdDailyRound -S $S -ElevateScript (Join-Path $PSScriptRoot 'daily-clear.ps1') -BoundParams $PSBoundParameters -Gates $gates -Opt @{ Stage = $Stage; Farm = [bool]$Farm } -Force:$Force -DryRun:$DryRun -SkipCleanup:$SkipCleanup -NoElevate:$NoElevate -NameField ShortName -NoticeOwner '方舟' -Tag $Tag
exit $code
