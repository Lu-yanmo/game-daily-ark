# lib/ark-daily.ps1 — 方舟这一路的"日常动作"：状态标记 / 方案判定 / dry-run 预览 / 真正跑一轮
#
# 2026-09-23 内部拆分：函数体是从 daily-clear.ps1 逐字搬来的，只有两处形式上必须改：
#   1) 原来靠脚本作用域闭包拿 $S，现在改成显式 -S 参数；
#   2) 原来直接写 $results['ark']，现在把结果 return 出去，由入口脚本决定往哪儿存。
# 公开命令行(-AckArk / -ArkShopDone / -ArkStage / -Force)仍然长在 daily-clear.ps1 里 ——
# 本文件只管"给定这件事就干什么"，不管"用户敲了什么参数"。
#
# 依赖：调用方先点 lib\common.ps1、lib\ark-decisions.ps1(或聚合的 lib\decisions.ps1)、lib\maa.ps1。
# 这里不重复点，理由见 lib\decisions.ps1 开头的说明(重复点会把控制台编码再设一遍，白做工)。
# 拆单游戏仓库时，本文件 + ark-decisions + maa + common 就是方舟的全部依赖，不碰 m9a/mumu。

function Set-GdArkAck {
    <# -AckArk：确认"这个活动的图我自己手动打过了" → 之后日常才允许自动刷活动关卡 #>
    param([Parameter(Mandatory)]$S)
    $d = Get-ArkEvent -S $S -IgnoreShopDone
    if (-not $d.EventKey) { Write-GdLog "方舟当前没有待确认活动：$($d.Reason)" -Level WARN }
    else {
        Set-GdAckKey -Game 'ark' -Key $d.EventKey
        Write-GdLog "已确认方舟活动 $($d.EventKey)[$($d.EventTip)]→ 日常将刷 $($d.StageHint)" -Level OK
    }
}

function Set-GdArkShopState {
    <# -ArkShopDone / -ArkShopReset：标记或撤销"活动商店已领空"。-Done 为真=标记，为假=撤销 #>
    param([Parameter(Mandatory)]$S, [switch]$Done)
    $d = Get-ArkEvent -S $S -IgnoreShopDone
    if (-not $d.EventKey) { Write-GdLog "方舟当前没有进行中的活动可标记：$($d.Reason)" -Level WARN }
    elseif ($Done) {
        Set-GdShopDoneKey -Game 'ark' -Key $d.EventKey
        $idlePlan = Get-GdMapValue $S.ark.planByWeekday "$([int](Get-Date).DayOfWeek)"
        if (-not $idlePlan) { $idlePlan = $S.ark.defaultStage }
        Write-GdLog "已标记方舟活动 $($d.EventKey)[$($d.EventTip)] 商店领空 → 之后剩余理智只刷 $idlePlan" -Level OK
    }
    elseif (Remove-GdShopDoneKey -Game 'ark' -Key $d.EventKey) {
        Write-GdLog "已撤销 $($d.EventKey) 的领空标记 → 恢复自动刷活动代币" -Level OK
    } else {
        Write-GdLog "$($d.EventKey) 本来就没有领空标记" -Level WARN
    }
}

function Resolve-GdArkDecision {
    <# 命令行意图 -> 本轮方舟方案(含 -Stage 手动指定、-Force 跳过确认门)，并把"方舟方案：…"写进日志。
       参数故意叫 -Stage 而不是 -ArkStage：本文件只管方舟，带游戏前缀的名字留给合体入口 daily-clear.ps1。 #>
    param([Parameter(Mandatory)]$S, [string]$Stage, [switch]$Force)
    $ark = Get-ArkEvent -S $S
    if ($Stage) {
        $ark = [pscustomobject]@{ Mode = 'manual'; Stage = $Stage; StageHint = $Stage; ClearSanity = $true; Reason = "命令行指定刷 $Stage"; EventKey = $null; EventTip = $null; Source = 'manual' }
    }
    if ($Force -and $ark.Mode -eq 'event-pending') {
        $ark = [pscustomobject]@{ Mode = 'event'; Stage = $ark.StageHint; StageHint = $ark.StageHint; ClearSanity = $true; Reason = "(-Force) 跳过活动确认门，直接刷 $($ark.StageHint)"; EventKey = $ark.EventKey; EventTip = $ark.EventTip; Source = $ark.Source }
        Write-GdLog '-Force：本轮忽略活动确认门' -Level WARN
    }
    Write-GdLog "方舟方案：$($ark.Mode) — $($ark.Reason)"
    return $ark
}

function Show-GdArkPreview {
    <# -DryRun：只把"将要下发的 MAA 配置"和端游窗口状态打印出来，一个程序都不启动 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision)
    $prev = Set-MaaDailyConfig -S $S -Decision $Decision
    $prev.Changes | ForEach-Object { Write-GdLog "  MAA：$_" }
    $pattern = if ($S.ark.windowTitlePattern) { [string]$S.ark.windowTitlePattern } else { '明日方舟|Arknights' }
    $win = Get-GdWindowByTitle -Pattern $pattern
    Write-GdLog ("  端游窗口：" + $(if ($win) { "已存在 [$($win.Name)#$($win.Id)] $($win.Title)" } else { "没有 → 会先启动 $($S.paths.arknightsExe) 再让 MAA 连" }))
}

function Start-GdArkDaily {
    <# 真正跑一轮方舟：接管关闭 → 写配置 → 拉端游 → 跑 MAA → 该重试就重试 → 收尾。返回 @{Status;Detail;Duration} #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision)
    Write-GdLog '--- 方舟(端游 + MAA)---' -Level STEP
    $ark = $Decision
    $arkName = [System.IO.Path]::GetFileNameWithoutExtension($S.paths.arknightsExe)
    Invoke-GdTakeover -S $S -Names @((Get-MaaPaths -S $S).Name, $arkName) -Label '方舟/MAA'
    $maaCfg = Set-MaaDailyConfig -S $S -Decision $ark -Apply
    $maaCfg.Changes | ForEach-Object { Write-GdLog "  MAA：$_" }
    if ($ark.Mode -eq 'event-pending') {
        Write-GdLog "本轮跳过理智作战(只跑公招/基建/信用/领奖)；自己打过活动图后跑 daily-clear.ps1 $(Get-GdEntryVerb -Game ark -Verb Ack)" -Level WARN
    }
    $run = {
        # 拉端游必须在 $run 里面：重试前那句 Stop-MaaAndGame 是把端游和 MAA 一起关掉的，
        # 放在外面的话第二次只有 MAA 起来了、游戏没起来 → MAA 只会报"未找到窗口"，白烧一轮。
        # (2026-09-24 06:00 那一轮就是这么栽的：首轮卡在端游登录界面被判 stalled，重试直接 not-started。)
        if ($S.runtime.launchArkFromHelper -ne $false) {
            if (-not (Start-GdArkClient -S $S)) {
                Write-GdLog '端游窗口没等到：MAA 大概会报"未找到窗口"，仍继续(会按 not-started 早退)' -Level WARN
            }
        }
        Invoke-MaaRun -S $S -ExpectedChains $maaCfg.ExpectedChains
    }
    $r = Invoke-GdStep -Name '方舟' -Body $run
    if ($r.Status -notin @('ok', 'not-started', 'unknown-format') -and $S.runtime.retryOnce) {
        Write-GdLog '方舟本轮未成功 → 收尾后重试一次' -Level WARN
        Stop-MaaAndGame -S $S
        Start-Sleep -Seconds 25
        $r = Invoke-GdStep -Name '方舟重试' -Body $run
    } elseif ($r.Status -eq 'unknown-format') {
        Write-GdLog '方舟日志标志一条都没认出来 → 重试同样看不懂，直接记入本轮告警(见下面的处理建议)' -Level ERROR
    }
    if ($r.Status -eq 'not-started' -and -not (Test-GdAdmin)) {
        Write-GdLog '方舟这一路要管理员权限：去掉 -NoElevate(或用 run-daily.cmd / 计划任务)重跑即可自动提权' -Level ERROR
    }
    Stop-MaaAndGame -S $S
    return $r
}
