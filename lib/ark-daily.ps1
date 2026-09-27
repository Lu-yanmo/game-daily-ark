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
#
# ── 冻结(2026-09-27，PS→C# 批次 5)────────────────────────────────────────────
# Resolve-GdArkDecision 的**构造段规则**(-Stage 手造 manual、-Force 跳确认门、farm 专用轮重建、
# 需求优先去重合并、两段 WARN 文案)已迁到 tools\panel-cs\Orchestration.cs
# (verb：apply-ark-daily-intent；契约见 docs\ps-migration-batch0.md)。
# 壳里留的是"活"：Get-ArkEvent 取数、Resolve-GdArkFarmDecision(读账本/纠偏)、Farm 对象挂回、
# "方舟方案：…"日志行；Set-Gd*Ack/ShopState 与 Start-GdArkDaily 整函数留壳(起进程/写配置归后续批次)。
# 分两次调 verb 是刻意的：旧代码算 farmOpt 用的是 manual/force 变换**之后**的 ark ——
# -Stage 时旧代码不会进 append 档，一次调用会把这条顺序语义弄丢。改规则请改 C# 并跑
# tools\probe-orch-golden.ps1 对拍，不要在这里加规则。
# ──────────────────────────────────────────────────────────────────────────────
#
# ── 追加冻结(2026-09-27，PS→C# 批次 8)─────────────────────────────────────────
# Start-GdArkDaily 的重试分流(`Status -notin {ok,not-started,unknown-format}` ∧ retryOnce → 重试一次、
#  否则 unknown-format 落 ERROR 整句)已迁到 tools\panel-cs\Orchestration.cs(verb：decide-daily-retry，
#  -Game ark)。壳里留的正是"活"：Stop-MaaAndGame、sleep 25、重跑 $run、提权提示那记独立 if。
#  旧分流在原地逐行 # 前缀冻结(test-ark:163 钉 `Status -notin @(…)` 字面锚，别"顺手搬走")。
#  改分流规则/话术请改 Orchestration.cs 并复拍 tools\probe-live-golden.ps1，不要在这里加 if。
# ──────────────────────────────────────────────────────────────────────────────

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
    <# 转发壳(批次 5)：命令行意图 -> 本轮方舟方案的**构造规则**在 C#(apply-ark-daily-intent)，
       且按旧代码的顺序分两步喂：第一步只过 manual/force 变换，第二步拿变换后的 ark 去算 farmOpt 再过 farm 档。
       参数故意叫 -Stage / -Farm 而不是 -ArkStage / -ArkFarm：本文件只管方舟，带游戏前缀的名字留给合体入口 daily-clear.ps1。 #>
    param([Parameter(Mandatory)]$S, [string]$Stage, [switch]$Force, [switch]$Farm)
    $ark = Get-ArkEvent -S $S
    $d1 = Invoke-GdCli -Verb 'apply-ark-daily-intent' -Body ([pscustomobject]@{
        ark = $ark; stage = $Stage; force = [bool]$Force; farm = $false; farmOpt = $null
    })
    $ark = $d1.Ark
    foreach ($w in @($d1.Warnings)) { Write-GdLog $w -Level WARN }

    <# 材料补刷(ark-farm)：-Farm=专用轮(整条 Fight 就刷这些关)，否则长草方案上顺带追加。
       功能没装(这棵树没有 ark-farm.ps1)或本轮不该刷 → $farmOpt 为 $null，方案原样不动。 #>
    $farmOpt = $null
    if (Get-Command Resolve-GdArkFarmDecision -ErrorAction SilentlyContinue) {
        $farmOpt = Resolve-GdArkFarmDecision -S $S -Decision $ark -Dedicated:$Farm
    }
    $d2 = Invoke-GdCli -Verb 'apply-ark-daily-intent' -Body ([pscustomobject]@{
        ark = $ark; stage = ''; force = $false; farm = [bool]$Farm; farmOpt = $farmOpt
    })
    foreach ($w in @($d2.Warnings)) { Write-GdLog $w -Level WARN }
    $ark = $d2.Ark
    if ($d2.HasFarmFields) {
        # Farm 挂**原 PS 对象**而不是 JSON 回读件：接线层(maa.ps1)要拿它读 TargetDrop/TimesLimit 的现场形状
        $ark | Add-Member -NotePropertyName Farm -NotePropertyValue $farmOpt
        $ark | Add-Member -NotePropertyName FarmMode -NotePropertyValue ([string]$d2.FarmMode)
    }
    Write-GdLog "方舟方案：$($ark.Mode) — $($ark.Reason)"
    return $ark
}

function Show-GdArkPreview {
    <# -DryRun：只把"将要下发的 MAA 配置"和端游窗口状态打印出来，一个程序都不启动 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision)
    $prev = Set-MaaDailyConfig -S $S -Decision $Decision
    $prev.Changes | ForEach-Object { Write-GdLog "  MAA：$_" }
    if (Get-GdMapValue $Decision 'Farm') { Write-GdLog "  材料补刷：$($Decision.Farm.Reason)(档位=$($Decision.FarmMode))" }
    $pattern = if ($S.ark.windowTitlePattern) { [string]$S.ark.windowTitlePattern } else { '明日方舟|Arknights' }
    # 同 Start-GdArkClient：预览也要按进程名过滤，别让浏览器标签页冒充"端游窗口已存在"
    $arkName = if ($S.paths.arknightsExe) { [System.IO.Path]::GetFileNameWithoutExtension([string]$S.paths.arknightsExe) } else { $null }
    $win = Get-GdWindowByTitle -Pattern $pattern -ProcessName $arkName
    Write-GdLog ("  端游窗口：" + $(if ($win) { "已存在 [$($win.Name)#$($win.Id)] $($win.Title)" } else { "没有 → 会先启动 $($S.paths.arknightsExe) 再让 MAA 连" }))
}

function Start-GdArkDaily {
    <# 真正跑一轮方舟：接管关闭 → 写配置 → 拉端游 → 跑 MAA → 该重试就重试 → 收尾。返回 @{Status;Detail;Duration} #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision)
    Write-GdLog '--- 方舟(端游 + MAA)---' -Level STEP
    # 起跑前置判定(2026-09-26)：06:00 两轮都死在"会话被屏保/锁屏桌面接管"——输入进不来，
    # MAA 必然报"未找到窗口"，端游启动+等待白烧 12 分钟。桌面不对就直接记 not-started 早退，把原因写全。
    $desk = Get-GdInputDesktopName
    if ($desk -and $desk -ne 'Default') {
        # 把"当时屏保到底装着什么"一起写进原因：事后翻 history.csv 就知道是谁干的，
        # 不用再猜。读数函数只读注册表，读不到就说不知道，绝不因为这条把早退挡住。
        $svTxt = ''
        try {
            if (Get-Command Get-GdScreensaverVerdict -ErrorAction SilentlyContinue) {
                $svv = Get-GdScreensaverVerdict -Cfg (Get-GdScreensaverConfig)
                if ($svv) { $svTxt = [string]$svv.Detail }
            }
        } catch { $svTxt = '' }
        Write-GdLog "跳过本轮：输入桌面=$desk(屏保/锁屏已接管会话，鼠标键盘进不来；读不到桌面名不会走这条)" -Level WARN
        if ($svTxt) { Write-GdLog "  屏保读数：$svTxt" -Level WARN }
        $detail = "起跑时会话在 $desk 桌面(屏保/锁屏)，直接跳过；长期解法：把 Windows 屏保设为「(无)」——pwsh -File tools\unarm-screensaver.ps1 -Apply，或 设置→个性化→锁屏界面→屏幕保护程序→(无)；夜间保持解锁也行"
        if ($svTxt) { $detail += "。$svTxt" }
        return @{ Status = 'not-started'; Duration = 0; Detail = $detail }
    }
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
    <#
      ===== 批次 8：重试分流改问 decide-daily-retry(Orchestration.cs，-Game ark) =====
      跳过清单、retryOnce 合取与两句文案住在 C#；本壳只回放日志 + 落地"活"(收尾/重跑)。
      旧两分支逐行 # 前缀冻结在下方(test-ark:163 钉 `Status -notin @(…)` 字面锚)。
    #>
    #     if ($r.Status -notin @('ok', 'not-started', 'unknown-format') -and $S.runtime.retryOnce) {
    #         Write-GdLog '方舟本轮未成功 → 收尾后重试一次' -Level WARN
    #         Stop-MaaAndGame -S $S
    #         Start-Sleep -Seconds 25
    #         $r = Invoke-GdStep -Name '方舟重试' -Body $run
    #     } elseif ($r.Status -eq 'unknown-format') {
    #         Write-GdLog '方舟日志标志一条都没认出来 → 重试同样看不懂，直接记入本轮告警(见下面的处理建议)' -Level ERROR
    #     }
    $d = Invoke-GdCli -Verb 'decide-daily-retry' -Body ([pscustomobject]@{
        game      = 'ark'
        status    = [string]$r.Status
        retryOnce = [bool]$S.runtime.retryOnce
    })
    foreach ($l in @($d.Logs)) {
        $lvl = [string]$l.Level
        if ($lvl -and ($lvl -ne 'INFO')) { Write-GdLog ([string]$l.Text) -Level $lvl } else { Write-GdLog ([string]$l.Text) }
    }
    if ([bool]$d.Retryable) {
        Stop-MaaAndGame -S $S
        Start-Sleep -Seconds 25
        $r = Invoke-GdStep -Name '方舟重试' -Body $run
    }
    if ($r.Status -eq 'not-started' -and -not (Test-GdAdmin)) {
        Write-GdLog '方舟这一路要管理员权限：去掉 -NoElevate(或用 run-daily.cmd / 计划任务)重跑即可自动提权' -Level ERROR
    }
    Stop-MaaAndGame -S $S
    # 掉落记账放在收尾之后：MAA 关门前还会往 gui.log 补写最后的掉落统计行，偏移记在账本里，
    # 这一轮漏几行下一轮也会补上 —— 所以这段抛任何错都只 WARN，绝不影响本轮结论。
    try {
        $bn = Update-GdArkFarmLedger -S $S
        if ($bn) { Write-GdLog "掉落记账：$bn" }
    } catch { Write-GdLog "掉落记账没做起来：$($_.Exception.Message)(不影响本轮)" -Level WARN }
    return $r
}
