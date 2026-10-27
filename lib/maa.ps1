# lib/maa.ps1 — 配置并驱动 MAA(明日方舟端游 / Win32 控制器)
#
# ── 冻结(2026-09-26，PS→C# 批次 3；2026-10-27 随甲档第四刀刀②改口)──────────────
# 本体已迁到 tools\panel-cs\Processes.cs(契约见 docs\ps-migration-batch0.md)：
#   Get-MaaAsstStuckState → verb parse-asst-state(四个"当前状态"的抠法在 C#；inject 只反映滑基建的老教训也在那)
#   Get-MaaAsstStuckHint  → verb parse-asst-hint(线索话术整句在 C#)
#   Set-MaaDailyConfig 的规则段 → verb plan-maa-queue(队列开关/关卡校验/farm 两档九项/ExpectedChains
#       的 Select-Object -Unique 大小写敏感去重，全部在 C#；本壳保留：在跑检查、读写盘、备份、回读核对、日志染色)
# 所以：改规则/文案请改 Processes.cs 并跑 panel-cs --proctest 对真值，不要在这里加规则。
# 现势：监控循环 Invoke-MaaRun(旧 :220-620)已整函数出仓——循环骨架在核内 maa_run<H: MaaHost>
# (tools\rustcore\src\main.rs，判据外调 C#，生产 = maa_run + RealHost)；本文件只剩
# Get-MaaPaths/Start-GdArkClient/Stop-MaaAndGame(起进程、启动器页、进程树收尾)。
# ──────────────────────────────────────────────────────────────────────────────
#
# ── 追加冻结(2026-09-27，PS→C# 批次 5；2026-10-27 随摘件改口)──────────────────
# Invoke-MaaRun 轮询里"每行 gui.log 是什么"的分类段(五种标志的顺序判定、清洗正则、benign 命中、
# marker/logChars 计数)已迁到 tools\panel-cs\Orchestration.cs(verb：parse-maa-gui-lines)。
# 旧句"监控循环本体仍留本文件 / test-ark 钉着 `Status = 'unknown-format'` 字面"随 10-27 摘件作废：
#   循环本体已进核，unknown-format 金样由 panel-cs --looptest 接守(RunLoops.SelfTest.cs)。
# 改分类规则请改 C# 并跑 tools\panel-cs\build.ps1 -Verify(orchtest)。
# ──────────────────────────────────────────────────────────────────────────────
#
# ── 追加冻结(2026-09-27，PS→C# 批次 7 —— 活段第一刀；2026-10-27 随摘件改口)──────
# Invoke-MaaRun 每 tick 的早退判据梯(读不懂标志/没起来/点了没动/队列跑空/停滞告警/超时/静默/
#     进程探活/跑齐收尾 —— 十档的顺序、阈值、Detail 整句、兜底预算扣数、RecordTag 错位一格)
#     已迁到 tools\panel-cs\RunLoops.cs(verb：decide-maa-run-tick)。口径见 docs\ps-migration-live-caliber.md，
#     剧本对拍 = tools\panel-cs\build.ps1 -Verify 的 --looptest(基线钉 c498da0；原 live 门 10-26 摘件)。
# 旧句"本壳留下 while+sleep…三段执行块兼任 test-ark 的锚"随 10-27 摘件作废：循环骨架与三枚执行块
#     (真抢前台/真兜底/真记账，Grab→Rescue→Record 三笔账)整体进核(maa_run + RealHost)，
#     test-ark 咬壳内字面的那批格同批退役；判据唯一事实源在 C#／Rust。
#  批次 5 钉的 `$drained = $true` 回放锚不受影响，原样在 parse-maa-gui-lines 回灌段。
# ──────────────────────────────────────────────────────────────────────────────
#
# ── 追加冻结(2026-09-27，PS→C# 批次 9 —— 活段第三批：回灌+挂钟收尾)─────────────
# Invoke-MaaRun 的六档事件回灌 switch(finished/chain/stall/drained/error/benign 的逐档语义：
#     chain 大小写不敏感累计、error 满 40 无声封顶、benign 按 Pattern 首见、话术整句)已迁到
#     tools\panel-cs\RunLoops.cs(verb：apply-maa-gui-events)；出循环后的挂钟收尾三行
#     (OK 话术 Round(dur/60,1) 的数字形、"完成链路："拼串)搬进同一文件(verb：finish-maa-run)。
# 旧句"壳保留 tail 轮询/hashtable 重建/挂钟收尾、逐行 # 冻在原位别删"随 10-27 摘件作废：
#     那些行随函数整体出仓，test-ark 咬它们的格同批退役。
# 改话术/计数规则改 RunLoops.cs 并复跑 panel-cs --looptest(基线仍钉 c498da0；原 live 门 10-26 摘件)。
# ──────────────────────────────────────────────────────────────────────────────

function Get-MaaPaths {
    param([Parameter(Mandatory)]$S)
    # asst.log 是老配置里可能没有的一项(它只是线索，不是判定依据) → 给个 MAA 默认的相对路径兜底
    $asstRel = if ($S.paths.maaAsstLog) { [string]$S.paths.maaAsstLog } else { 'debug\asst.log' }
    return [pscustomobject]@{
        Dir     = $S.paths.maaDir
        Exe     = (Join-GdPath $S.paths.maaDir @($S.paths.maaExe))
        Config  = (Join-GdPath $S.paths.maaDir @($S.paths.maaConfig))
        GuiLog  = (Join-GdPath $S.paths.maaDir @($S.paths.maaGuiLog))
        AsstLog = (Join-GdPath $S.paths.maaDir @($asstRel))
        Name    = [System.IO.Path]::GetFileNameWithoutExtension($S.paths.maaExe)
    }
}

function Get-GdMaaFightSkip {
    <# 认关止损(2026-09-28 新增)：从 gui.log 读 MAA 本轮的跳关回执。
       判定本体在 C#(detect-maa-fight-skip，Orchestration.cs)：只押最后一次 GUI started 之后、
       「关卡计划内没有当日开放的关卡」这一句；「理智作战: … 任务跳过」理智已满等其它起因也会出，
       只作旁证计数。本壳只做现场读盘(Get-GdFileTail 全量)与形状整理，不加任何 if 判定。 #>
    param([Parameter(Mandatory)]$S)
    $P = Get-MaaPaths -S $S
    if (-not (Test-Path -LiteralPath $P.GuiLog)) { return $null }
    $tail = Get-GdFileTail -Path $P.GuiLog -Offset 0
    if (-not $tail.Text) { return $null }
    $d = Invoke-GdCli -Verb 'detect-maa-fight-skip' -Body ([pscustomobject]@{ text = [string]$tail.Text })
    return [pscustomobject]@{
        Skipped   = [bool]$d.Skipped
        Plan      = @($d.Plan)
        TaskSkips = [int]$d.TaskSkips
        Evidence  = @($d.Evidence)
    }
}

function Get-GdMaaStageObservation {
    <# 只读观测(B 档 #21，2026-10-05 新增)：从两份日志 tail 抄本轮的三对真值读数 ——
       asst.log 的 append_task Fight stage 与 LastOrCurBattleBegin 重放、gui.log 的
       GetFightStage from/selected(MAA 眼里今天开着的关名单)。判定本体在 C#
       (observe-maa-stage-open，Orchestration.cs)，本壳只做现场读盘与形状整理，不加任何 if 判定。
       它只给观测账本喂数(成案永远由人做)，不参与任何轮内决策。 #>
    param([Parameter(Mandatory)]$S)
    $P = Get-MaaPaths -S $S
    $asstText = ''
    if (Test-Path -LiteralPath $P.AsstLog) {
        # 观测只押"最后一班"：asst.log 连日不轮转能涨到几十 MB(本机 bak 实测 67MB)，整份喂 CLI 不划算。
        # 取尾部 16MB 窗口；若恰好日志已轮转变小，Get-GdFileTail 对越界 offset 会归零全读(小文件无伤)。
        $al = [long](Get-Item -LiteralPath $P.AsstLog).Length
        $ta = Get-GdFileTail -Path $P.AsstLog -Offset ([Math]::Max(0, $al - 16777216))
        if ($ta.Text) { $asstText = [string]$ta.Text }
    }
    $guiText = ''
    if (Test-Path -LiteralPath $P.GuiLog) {
        $tg = Get-GdFileTail -Path $P.GuiLog -Offset 0
        if ($tg.Text) { $guiText = [string]$tg.Text }
    }
    if (-not $asstText -and -not $guiText) { return $null }
    $d = Invoke-GdCli -Verb 'observe-maa-stage-open' -Body ([pscustomobject]@{
        asstText = $asstText
        guiText  = $guiText
        date     = (Get-Date).ToString('yyyy-MM-dd')
    })
    return [pscustomobject]@{
        Found      = [bool]$d.Found
        Date       = [string]$d.Date
        Stage      = [string]$d.Stage
        LastBattle = [bool]$d.LastBattle
        SawGuiPlan = [bool]$d.SawGuiPlan
        Survivors  = @($d.Survivors)
        Selected   = [string]$d.Selected
    }
}

function Get-MaaAsstStuckState {
    <#
      转发壳(parse-asst-state)：四个"当前状态"的抠法与 inject≠点击通道的实测教训都在 Processes.cs 注释里。
      返回形状保持旧 hashtable @{Task;Exec;Clicks;Inject}(核内 maa_run 侧按键取用)。
      空文本壳内早退：轮询里这是高频路径，别为空串起进程。
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @{ Task = ''; Exec = 0; Clicks = 0; Inject = 0 } }
    $d = Invoke-GdCli -Verb 'parse-asst-state' -Body ([pscustomobject]@{ text = [string]$Text })
    return @{ Task = [string]$d.Task; Exec = [int]$d.Exec; Clicks = [int]$d.Clicks; Inject = [int]$d.Inject }
}

function Get-MaaAsstStuckHint {
    <#
      转发壳(parse-asst-hint)：从 asst.log 挑"卡在哪个子任务、重复多少次、最后点到哪"的话术本体在 Processes.cs，
      为什么要单独读 asst.log、以及两句被推翻的错结论(中秋窗口/PostMessage 退化)也记在那边注释里 —— 别加回来。
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $d = Invoke-GdCli -Verb 'parse-asst-hint' -Body ([pscustomobject]@{ text = [string]$Text })
    return [string]$d.Hint
}

function Set-MaaDailyConfig {
    <#
      按今天的判定结果改写 MAA 的队列开关；写前备份、写后回读校验。
      MAA 必须在运行外部关闭状态才能改(否则退出时会被覆盖)。
      转发壳(plan-maa-queue)：规则段本体在 Processes.cs，这里只剩现场检查/读写盘/回放日志/回读核对。
    #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision, [switch]$Apply)

    $P = Get-MaaPaths -S $S
    if (Test-GdProcessRunning -Name $P.Name) {
        # 真正要写配置时必须先关掉(否则 MAA 退出时会把改动覆盖)；只预览则不影响
        if ($Apply) { throw "MAA 正在运行，请先关闭再改配置" }
        Write-GdLog 'MAA 正在运行：预览不受影响，真正跑时会先接管关闭(残留的高权限 MAA 需要由提权那一轮来收)' -Level WARN
    }
    if (-not (Test-Path -LiteralPath $P.Config)) { throw "MAA 配置不存在：$P.Config" }

    $cfg = Read-GdJson -Path $P.Config

    <#
      规则段整段递给 plan-maa-queue(开关怎么算/farm 两档九项/关卡校验/去重口径全在 Processes.cs)。
      账本口径(farm 缺口、场次)在壳这侧从 Decision.Farm 抠成平铺参数 —— verb 不认 Decision 的形状。
    #>
    $farmPlan = Get-GdMapValue $Decision 'Farm'
    $farmActive = [bool]($farmPlan -and [bool](Get-GdMapValue $farmPlan 'Active'))
    $farmMode = [string](Get-GdMapValue $Decision 'FarmMode')
    $d = Invoke-GdCli -Verb 'plan-maa-queue' -Body ([pscustomobject]@{
        config              = $cfg
        wantFinish          = [string]$S.ark.finishAllSanityWith
        alsoEnableMainFight = [bool]$S.ark.alsoEnableMainFight
        launchArkFromHelper = [bool]$S.runtime.launchArkFromHelper
        keepOn              = @($S.ark.keepQueuesEnabled)
        turnOff             = @($S.ark.disableQueues)
        table               = (Get-GdStageTable -S $S)
        mode                = [string]$Decision.Mode
        clearSanity         = [bool]$Decision.ClearSanity
        stage               = [string]$Decision.Stage
        farmActive          = $farmActive
        farmMode            = $farmMode
        farmItemId          = $(if ($farmPlan) { [string](Get-GdMapValue $farmPlan 'ItemId') } else { '' })
        farmGap             = $(if ($farmPlan) { [int](Get-GdMapValue $farmPlan 'Gap') } else { 0 })
        farmTarget          = $(if ($farmPlan) { [int](Get-GdMapValue $farmPlan 'Target') } else { 0 })
        farmTimes           = $(if ($farmPlan) { [int](Get-GdMapValue $farmPlan 'Times') } else { 0 })
    })

    <# 旧实现里"活动关卡不在表里(WARN)/理智计划(INFO)"两句是算规则时顺手打的，现在随 Logs 数组按序回放 #>
    foreach ($l in @($d.Logs)) {
        $lvl = [string]$l.Level
        if ($lvl -and ($lvl -ne 'INFO')) { Write-GdLog ([string]$l.Text) -Level $lvl } else { Write-GdLog ([string]$l.Text) }
    }
    $changes = @(foreach ($c in @($d.Changes)) { [string]$c })
    $expected = @(foreach ($c in @($d.ExpectedChains)) { [string]$c })
    $stageText = [string]$d.Stage

    if ($Apply -and $changes.Count -gt 0) {
        <# 写盘的就是 C# 改好的树(NewConfig)；回读核对留在壳里 —— 写失败/被 MAA 覆盖要立刻报警，这条纪律不过夜 #>
        $bak = Backup-GdFile -Path $P.Config
        Write-GdJson -Path $P.Config -Object $d.NewConfig
        $intent = [ordered]@{}
        foreach ($i in @($d.Intent)) { $intent[[string]$i.Name] = [bool]$i.Enable }
        $verify = Read-GdJson -Path $P.Config
        $bad = @()
        foreach ($q in @($verify.Configurations.Default.TaskQueue)) {
            $n = [string]$q.Name
            if (-not $intent.Contains($n)) { continue }
            if ([bool]$q.IsEnable -ne [bool]$intent[$n]) { $bad += "$n(期望 $($intent[$n])，实际 $($q.IsEnable))" }
        }
        if ($bad.Count) { throw "MAA 配置回读不一致：$($bad -join '; ')(备份：$(Split-Path -Leaf $bak))" }
        Write-GdLog "MAA 配置已更新并校验通过(备份：$(Split-Path -Leaf $bak))" -Level OK
    }
    if ($changes.Count -eq 0) { $changes = @('(无需改动)') }

    return [pscustomobject]@{
        Path = $P.Config
        Changes = $changes
        ExpectedChains = $expected
        Stage = $stageText
        Applied = [bool]$Apply
    }
}

function Wait-GdArkLauncherReady {
    <#
      10-11 新增：把"端游停在启动器的更新页上"这一格变成自动处理。
      由来：2026-10-11 06:00 那班，端游到版本日就停在更新页等有人点『更新』，而旧判定只等"窗口标题出现"——
      更新页的标题和主界面**都是"明日方舟"**(那班日志里的"端游窗口就绪 [Arknights#31564]"拍到的就是启动器页)，
      于是照样放行、MAA 对着一个还没进游戏的页面把五个任务全跑错(14m23s)。标题分不开，只有画面分得开。

      分工照内核化的老规矩：判据(五档相位、话术、点击预算、千分比→客户区的换算、越界拒绝)全在 C# 的
      check-ark-launcher(Live.cs)；这里只做"活"——循环、睡眠、真点击、落日志。
      语义是**止损，不是新闸门**：任何一档判不出(uncertain)、内核问不动、开关关掉、dry-run 都返回 $true 放行，
      这一枚坏了不许把日常链拦死；只有"到上限还没进游戏"和"窗口没了"才回 $false(调用方照旧按"仍继续"走)。
      花费口径：每一轮最多问模型 arkLauncherMaxChecks 次(默认 6 次)，下载等待上限 arkUpdateWaitSeconds 秒(默认 2400)。
    #>
    param([Parameter(Mandatory)]$S, [switch]$DryRun)

    # 开关语义与 arkVisionRescue 同一条：没写就是开着，只有明写成 $false 才关(关了 = 回到 10-11 之前的旧行为)。
    if ($S.runtime.arkAutoUpdateClick -eq $false) { return $true }
    if ($DryRun) { Write-GdLog '[dry-run] 跳过启动器更新页检查' -Level STEP; return $true }

    $waitSec = [int]$S.runtime.arkUpdateWaitSeconds
    if ($waitSec -le 0) { $waitSec = 2400 }
    $maxClicks = [int]$S.runtime.arkLauncherMaxChecks
    if ($maxClicks -le 0) { $maxClicks = 6 }      # C# 侧同一档兜底，两边都不许让配置一坏就变成"一次都不点"
    $deadline = (Get-Date).AddSeconds($waitSec)
    $clicks = 0
    $checks = 0

    while ((Get-Date) -lt $deadline) {
        $d = $null
        try {
            $d = Invoke-GdCli -Verb 'check-ark-launcher' -Body ([pscustomobject]@{
                clicksAlready = [int]$clicks
                maxClicks     = [int]$maxClicks
            })
        } catch {
            Write-GdLog "启动器检查：这一枚问不动($($_.Exception.Message))，分不清是不是更新页，按原样放行" -Level WARN
            return $true
        }
        $checks++
        $lvl = [string]$d.Level
        if ($d.LogLine) {
            if ($lvl -and ($lvl -ne 'INFO')) { Write-GdLog ([string]$d.LogLine) -Level $lvl } else { Write-GdLog ([string]$d.LogLine) }
        }
        switch ([string]$d.Phase) {
            'clear'       { return $true }
            'no-window'   { return $false }       # 窗口都没了，检查没有对象(等下去也不会自己长回来)
            'uncertain'   { return $true }        # 判不出 = 交回原路，不拦
            'needs-click' {
                $c = $null
                try {
                    $c = Invoke-GdCli -Verb 'ark-window-click' -Body ([pscustomobject]@{
                        handle  = [long]$d.Handle
                        clientX = [int]$d.ClientX
                        clientY = [int]$d.ClientY
                        name    = '启动器窗口'
                        what    = [string]$d.What
                        why     = [string]$d.Why
                    })
                } catch {
                    Write-GdLog "启动器检查：点击没发出去($($_.Exception.Message))，按原样放行" -Level WARN
                    return $true
                }
                $clicks++
                # 不用 ark-window-click 那句 "视觉兜底：…" 的日志：那一串说的是关弹窗，这里说的是点『更新』。
                if ([bool]$c.Sent) { Write-GdLog "启动器检查：已点下去($([string]$c.Mode))，等它开始拉资源" -Level STEP }
                else { Write-GdLog "启动器检查：这一下没点实($([string]$c.Mode))，再看看" -Level WARN }
                Start-Sleep -Seconds 30
                continue
            }
            'waiting'     { Start-Sleep -Seconds 60; continue }
            default       {
                Write-GdLog "启动器检查：认不出这一档相位([$([string]$d.Phase)])，按原样放行" -Level WARN
                return $true
            }
        }
    }
    Write-GdLog "启动器检查：等了 $waitSec 秒(问模型 $checks 次、点过 $clicks 次)还没进游戏，这一轮到此为止" -Level WARN
    return $false
}

function Start-GdArkClient {
    <#
      MAA 的配置里并没有存端游路径(实测 StartGame=true 也只会报"未找到窗口")，
      所以由日常脚本自己把客户端拉起来，再让 MAA 去连。
    #>
    param([Parameter(Mandatory)]$S, [switch]$DryRun)

    $exe = [string]$S.paths.arknightsExe
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { throw "端游路径不对：$exe(改 settings.paths.arknightsExe)" }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($exe)
    $pattern = if ($S.ark.windowTitlePattern) { [string]$S.ark.windowTitlePattern } else { '明日方舟|Arknights' }

    # 带进程名过滤：只认真·端游(Arknights.exe)，浏览器标签页撞标题不算
    $win = Get-GdWindowByTitle -Pattern $pattern -ProcessName $name
    if ($win) { Write-GdLog "端游窗口已存在：[$($win.Name)#$($win.Id)] $($win.Title)"; return $true }

    if (Test-GdProcessRunning -Name $name) {
        Write-GdLog "端游进程在跑但还没有窗口($name)，等它出登录界面" -Level WARN
    } else {
        Write-GdLog "启动端游：$exe" -Level STEP
        if ($DryRun) { Write-GdLog '[dry-run] 跳过实际启动' -Level STEP; return $false }
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
    }

    $haveWindow = Wait-GdCondition -Test { [bool](Get-GdWindowByTitle -Pattern $pattern -ProcessName $name) } `
        -TimeoutSeconds ([int]$S.runtime.arkWindowTimeoutSeconds) -PollSeconds 5 -What '端游窗口'
    if ($haveWindow) {
        $win = Get-GdWindowByTitle -Pattern $pattern -ProcessName $name
        Write-GdLog "端游窗口就绪：[$($win.Name)#$($win.Id)] $($win.Title)" -Level OK
        Start-Sleep -Seconds ([int]$S.runtime.arkWarmupSeconds)   # 让它自己登录/进主界面
        # 10-11：标题就绪不等于进到了游戏(更新页同名)。这一句是新增的一层"按画面确认"，判不出会照旧放行。
        return [bool](Wait-GdArkLauncherReady -S $S -DryRun:$DryRun)
    }
    Write-GdLog "等了 $([int]$S.runtime.arkWindowTimeoutSeconds) 秒还没看到端游窗口(要登录/在更新/路径不对?)" -Level WARN
    return $false
}

function Stop-MaaAndGame {
    param([Parameter(Mandatory)]$S)
    $P = Get-MaaPaths -S $S
    if ($S.runtime.quitAssistantAfter) {
        $n = Stop-GdProcessTree -Name $P.Name
        if ($n) { Write-GdLog "已关闭 MAA($n 个进程)" }
    }
    if ($S.runtime.closeArknightsAfter -and $S.paths.arknightsExe) {
        $n = Stop-GdProcessTree -Name ([System.IO.Path]::GetFileNameWithoutExtension($S.paths.arknightsExe))
        if ($n) { Write-GdLog "已关闭明日方舟端游($n 个进程)" }
    }
}
