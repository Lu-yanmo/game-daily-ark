<#
  daily-clear.ps1 — 《明日方舟》端游 + MAA 每日清体力(单游戏仓库入口)

  .\daily-clear.ps1 -DryRun          # 只看今天会怎么跑，不碰任何程序
  .\daily-clear.ps1                  # 完整跑一轮
  .\daily-clear.ps1 -Ack             # 确认"新活动的图我自己手动打过了"→ 之后每天自动刷活动关卡
  .\daily-clear.ps1 -ShopDone        # 确认"活动商店已领空"→ 剩余理智改刷长草计划
  .\daily-clear.ps1 -ShopReset       # 撤销上面的领空标记(误点/活动又开新一批兑换)
  .\daily-clear.ps1 -Stage SK-5      # 临时指定刷哪几关(逗号分隔，会拿 MAA 的关卡表校验)
  .\daily-clear.ps1 -SkipCleanup     # 跑完不关端游/MAA(自己接着玩)
  .\daily-clear.ps1 -NoElevate       # 禁止自动提权(只在看输出时用；真跑大概率连不上端游)
  计划任务每日按 config\settings.json 的 schedule.times 调用：daily-clear.ps1 -Tag auto
  权限：端游 + MAA 要管理员。非提权运行时脚本会弹一次 UAC 并以管理员身份重跑自己(-NoElevate 可禁止)。

  退出码：0=这一轮判定为完成；2=没完成(细节看 logs\ 里那一轮的日志和通知气泡)。
#>
# 双引擎兼容：Windows PowerShell 5.1(系统自带) 与 PowerShell 7 都要能跑，别再加 #Requires 版本门把访客挡在门外。
[CmdletBinding()]
param(
    [ValidateSet('auto', 'manual')][string]$Tag = 'manual',
    [switch]$DryRun,
    [Alias('ConfirmEvent')][switch]$Ack,
    [Alias('MarkShopDone')][switch]$ShopDone,
    [switch]$ShopReset,
    [switch]$SkipCleanup,
    [switch]$Force,
    [switch]$NoElevate,
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'lib\decisions.ps1')      # 门面：仓库里有哪些判定文件就点哪些
. (Join-Path $PSScriptRoot 'lib\maa.ps1')
. (Join-Path $PSScriptRoot 'lib\vision-rescue.ps1')   # 可选：停滞时把画面交给视觉模型的兜底(maa.ps1 按函数在不在决定用不用)
. (Join-Path $PSScriptRoot 'lib\ark-daily.ps1')

Start-GdTranscript -Tag "daily-$Tag"
Write-GdLog "=== 方舟日常开始(tag=$Tag, dryRun=$DryRun)===" -Level STEP

# 没配置这件事由脚本自己用日志的格式说清楚就走(-TellAndExit)：裸 throw 到了顶层是一屏
# "Exception: C:\...\common.ps1:120 / Line | ..." 那种内部报错，双击的人只会以为程序坏了。
$S = Get-GdSettings -TellAndExit
$envOk = @()
$envBad = @()
foreach ($probe in @(
        @{ N = 'MAA 目录'; P = $S.paths.maaDir },
        @{ N = 'MAA 配置'; P = (Join-GdPath $S.paths.maaDir @($S.paths.maaConfig)) },
        @{ N = '方舟端游'; P = $S.paths.arknightsExe }
    )) {
    if (Test-GdPathReady $probe.P) { $envOk += $probe.N } else { $envBad += "$($probe.N) → $(if ($probe.P) { $probe.P } else { '(没填)' })" }
}
Write-GdLog "环境检查：$($envOk.Count) 项就绪"
if ($envBad.Count) {
    $envBad | ForEach-Object { Write-GdLog "缺失：$_" -Level ERROR }
    throw '环境不完整，见上面缺失项(可跑 setup.ps1 或改 config\settings.json 的路径)'
}

# ---------- 权限闸门：端游 + MAA 需要管理员 ----------
if ($S.runtime.arkRequiresElevation -ne $false) {
    if (Test-GdAdmin) {
        Write-GdLog '管理员权限已具备(端游/MAA 需要)'
    }
    elseif ($NoElevate) {
        Write-GdLog '非管理员且指定了 -NoElevate：MAA 连不上端游，这一轮大概率 not-started' -Level WARN
    }
    elseif ($DryRun) {
        Write-GdLog '非管理员：dry-run 无所谓，真正跑时会自动提权(弹一次 UAC)' -Level WARN
    }
    else {
        Write-GdLog '端游要管理员权限(MAA 未提权时连不上客户端) → 以管理员身份重启本轮，请在 UAC 弹窗点「是」' -Level WARN
        $code = Start-GdElevatedSelf -Script (Join-Path $PSScriptRoot 'daily-clear.ps1') -Bound $PSBoundParameters -Force @('-NoElevate')
        Write-GdLog "提权子轮结束，退出码 $code(它的日志同样写在 logs\，不在本文件里)" -Level $(if ($code -eq 0) { 'OK' } else { 'WARN' })
        exit $code
    }
}

# ---------- 活动确认门 / 商店领空标记(具体动作在 lib\ark-daily.ps1) ----------
if ($Ack) { Set-GdArkAck -S $S }
if ($ShopDone -or $ShopReset) { Set-GdArkShopState -S $S -Done:$ShopDone }
if ($Ack -or $ShopDone -or $ShopReset) {
    if ($DryRun) { Write-GdLog '[dry-run] 仅记录确认/领空状态，结束'; exit 0 }
    Write-GdLog '状态已更新；继续执行本轮日常'
}

# ---------- 判定 ----------
$ark = Resolve-GdArkDecision -S $S -Stage $Stage -Force:$Force

if ($DryRun) {
    Write-GdLog '[dry-run] 预览将要下发的配置，不启动任何程序' -Level STEP
    Show-GdArkPreview -S $S -Decision $ark
    Write-GdLog '[dry-run] 完成' -Level OK
    exit 0
}

# ---------- 运行 ----------
if ($S.runtime.blockSleep) { Enter-GdNoSleep -KeepScreenOn ([bool]$S.runtime.keepScreenOn) }
$fatal = $null
try {
    $r = Start-GdArkDaily -S $S -Decision $ark
} catch {
    $fatal = $_.Exception.Message
    Write-GdLog "本轮异常中断：$fatal" -Level ERROR
    $r = @{ Status = 'error'; Detail = $fatal; Duration = 0 }
} finally {
    if (-not $SkipCleanup) {
        Write-GdLog '--- 收尾 ---' -Level STEP
        Stop-MaaAndGame -S $S
        Get-Process -Name 'MaaAgentBinary' -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch { } }
    }
    Exit-GdNoSleep
}

# ---------- 汇总 + 历史 + 通知 ----------
$ok = ($r.Status -eq 'ok') -and -not $fatal
$mins = if ($r.Duration) { " $([math]::Round($r.Duration / 60, 1)) 分钟" } else { '' }
$summary = "方舟：$($r.Status)$mins — $($r.Detail)"
Add-GdHistory -Game 'ark' -Status $r.Status -Mode $ark.Mode -Detail $r.Detail -DurationSec $r.Duration
Write-GdLog "=== 本轮结束：$(if ($ok) { '完成' } else { '需要人工看一眼' }) ===" -Level $(if ($ok) { 'OK' } else { 'WARN' })
Write-Host $summary

$noticeText = "方舟：$($ark.Mode)`n$summary"
if (-not $ok) { $noticeText += "`n(详情见 logs\$([System.IO.Path]::GetFileName($global:GD.LogFile)))" }
Send-GdNotice -Title $(if ($ok) { '方舟日常已完成' } else { '方舟日常需要人工看一眼' }) -Text $noticeText -Level $(if ($ok) { 'OK' } else { 'WARN' })

exit $(if ($ok) { 0 } else { 2 })
