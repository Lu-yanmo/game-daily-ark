# lib/maa.ps1 — 配置并驱动 MAA(明日方舟端游 / Win32 控制器)
#
# ── 冻结(2026-09-26，PS→C# 批次 3)────────────────────────────────────────────
# 本体已迁到 tools\panel-cs\Processes.cs(契约见 docs\ps-migration-batch0.md)：
#   Get-MaaAsstStuckState → verb parse-asst-state(四个"当前状态"的抠法在 C#；inject 只反映滑基建的老教训也在那)
#   Get-MaaAsstStuckHint  → verb parse-asst-hint(线索话术整句在 C#)
#   Set-MaaDailyConfig 的规则段 → verb plan-maa-queue(队列开关/关卡校验/farm 两档九项/ExpectedChains
#       的 Select-Object -Unique 大小写敏感去重，全部在 C#；本壳保留：在跑检查、读写盘、备份、回读核对、日志染色)
# 所以：改规则/文案请改 Processes.cs 并跑 panel-cs --proctest 对真值，不要在这里加规则。
# 故意留在 PS 侧的：Get-MaaPaths(读配置)、Invoke-MaaRun/Start-GdArkClient/Stop-MaaAndGame
# (起进程、轮询、视觉兜底、进程树收尾 —— 归批次 5 编排层)。
# ──────────────────────────────────────────────────────────────────────────────
#
# ── 追加冻结(2026-09-27，PS→C# 批次 5)────────────────────────────────────────
# Invoke-MaaRun 轮询里"每行 gui.log 是什么"的分类段(五种标志的顺序判定、清洗正则、benign 命中、
# marker/logChars 计数)已迁到 tools\panel-cs\Orchestration.cs(verb：parse-maa-gui-lines)。
# 监控循环本体(Start-Process/轮询/兜底/asst.log 线索/早退判定)仍留本文件 —— 那是"活段"，后续批次再谈。
# test-ark 钉着本文件必须原样存在 `Status = 'unknown-format'` 字面(unknown-format 早退分支故意留壳)，
# 改壳时别把它"顺手搬走"。改分类规则请改 C# 并跑 tools\panel-cs\build.ps1 -Verify(orchtest)。
# ──────────────────────────────────────────────────────────────────────────────
#
# ── 追加冻结(2026-09-27，PS→C# 批次 7 —— 活段第一刀)────────────────────────────
# Invoke-MaaRun 每 tick 的早退判据梯(读不懂标志/没起来/点了没动/队列跑空/停滞告警/超时/静默/
#     进程探活/跑齐收尾 —— 十档的顺序、阈值、Detail 整句、兜底预算扣数、RecordTag 错位一格)
#     已迁到 tools\panel-cs\RunLoops.cs(verb：decide-maa-run-tick)。口径见 docs\ps-migration-live-caliber.md，
#     剧本对拍 = tools\panel-cs\build.ps1 -Verify 的 --looptest(基线钉 c498da0；原 live 门 10-26 摘件)。
# 本壳留下的正是口径文档划给"活"的部分：while+sleep、起 MAA、tail 轮询、真抢前台/真兜底/真记账、挂钟收尾。
# 壳里那三段"执行块"是 effect 的落地处，也兼任 test-ark 的锚(记账三笔、档位顺序)——
#     判据唯一事实源在 C#：改规则/文案改 RunLoops.cs 并复拍，别再往这里加 if。
# (批次 5 头注"监控循环本体…早退判定仍留本文件"到本批作废一半：早退判据已走，循环骨架还在；
#  `Status = 'unknown-format'` 字面改由 return 构造的 switch 逐档保留，仍不许"顺手合并"。
#  批次 5 钉的 `$drained = $true` 回放锚不受影响，原样在 parse-maa-gui-lines 回灌段。)
# ──────────────────────────────────────────────────────────────────────────────
#
# ── 追加冻结(2026-09-27，PS→C# 批次 9 —— 活段第三批：回灌+挂钟收尾)─────────────
# Invoke-MaaRun 的六档事件回灌 switch(finished/chain/stall/drained/error/benign 的逐档语义：
#     chain 大小写不敏感累计、error 满 40 无声封顶、benign 按 Pattern 首见、话术整句)已迁到
#     tools\panel-cs\RunLoops.cs(verb：apply-maa-gui-events)；出循环后的挂钟收尾三行
#     (OK 话术 Round(dur/60,1) 的数字形、"完成链路："拼串)搬进同一文件(verb：finish-maa-run)。
# 壳保留的现场量：tail 轮询、markers/logChars += 计数、$completed/$benignSeen 两个 hashtable 的
#     重建、挂钟 $dur 与 Sort-Object 链表。旧两段逐行 # 冻在原位(`任务已完成，但出现错误`、
#     `$drained = $true` 这些 test-ark 字面锚就在冻结行里，substring 照命中，别删)。
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
      返回形状保持旧 hashtable @{Task;Exec;Clicks;Inject}(Invoke-MaaRun 直接按键取用)。
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

function Invoke-MaaRun {
    <# 启动 MAA → 解析 debug\gui.log 判定完成/停滞/失败 #>
    param(
        [Parameter(Mandatory)]$S,
        [Parameter(Mandatory)][string[]]$ExpectedChains,
        [switch]$DryRun
    )
    $P = Get-MaaPaths -S $S
    if ($DryRun) { Write-GdLog "[dry-run] 将启动 $P.Exe(自动开始队列：$($ExpectedChains -join ', '))" -Level STEP; return @{ Status = 'dryrun'; Detail = '' } }

    $expectedCount = @{}
    foreach ($c in $ExpectedChains) { $expectedCount[$c] = 1 }

    $offset = 0
    if (Test-Path -LiteralPath $P.GuiLog) { $offset = (Get-Item -LiteralPath $P.GuiLog).Length }
    $asstOffset = 0
    $asstHint = ''
    $rescues = @()             # 视觉兜底的每次尝试都记一句，最后拼进结论(见下面的 $detail)
    $rescueLeft = [int]$S.runtime.visionMaxRescue
    if ($rescueLeft -le 0) { $rescueLeft = 2 }     # 一轮最多兜底这么多次，别跟模型没完没了
    if ($P.AsstLog -and (Test-Path -LiteralPath $P.AsstLog)) { $asstOffset = (Get-Item -LiteralPath $P.AsstLog).Length }
    $started = Get-Date
    Write-GdLog "启动 MAA：$($P.Exe)" -Level STEP
    Start-Process -FilePath $P.Exe -WorkingDirectory $P.Dir | Out-Null
    if (-not (Wait-GdCondition -Test { Test-GdProcessRunning -Name $P.Name } -TimeoutSeconds 90 -PollSeconds 3 -What 'MAA 进程启动')) {
        return @{ Status = 'error'; Detail = 'MAA 未能启动(进程未出现)' }
    }
    <# 一开跑就把"这一轮的点击环境长什么样"记进日志：输入桌面 + 端游在不在前台 + 窗口状态。
       为什么要记 —— 无人值守那几轮的失败全是同一个样子(22 分钟无输出、点击全落空)，但日志里没有任何一句话
       能说明当时是"锁屏/窗口不在前台"还是"有个窗口挡着"，事后只能翻 asst.log 猜。这一行当时就把它记下来。
       这棵树上没有探测函数(1999 仓库、自检假环境)就跳过，不影响正常一轮。 #>
    if (Get-Command Get-GdArkDesktopState -ErrorAction SilentlyContinue) {
        try {
            $hwnd = $null
            if (Get-Command Get-GdArkWindow -ErrorAction SilentlyContinue) {
                $gw = Get-GdArkWindow -S $S
                if ($gw) { $hwnd = $gw.Handle }
            }
            $dstProbe = Get-GdArkDesktopState -Hwnd $hwnd
            Write-GdLog "点击环境探测：$($dstProbe.Detail)" $(if ($dstProbe.GameOnFg) { 'INFO' } else { 'WARN' })
        } catch { Write-GdLog "点击环境探测没做起来：$($_.Exception.Message)" -Level WARN }
    }

    $lastGrowth = Get-Date
    $completed = @{}
    $errors = @()
    $chanClicks = 0             # asst.log 里 Win32Controller click 的条数(整轮累计，只是规模参考)
    $stuckTask = ''             # asst.log 最后一次报出来的子任务
    $stuckExec = 0              # 它已经重试到第几次 —— 卡住时这个数会一路涨(实测 311)
    $chanGrabAt = $null         # 判到"点了没动"之后自己抢前台的时刻，抢完再给它 60 秒
    $benignSeen = @{}
    $seen = ''
    $markers = 0                # 认出的标志行数(完成/链路/停滞/异常)：一直是 0 = 日志看不懂了 → unknown-format
    $logChars = 0               # 读到的新增日志字符数：分得清"没写日志"和"写了但不认识"
    $finished = $false          # MAA 自己宣布"任务已全部完成"
    $drained = $false           # MAA 宣布"跑完了但有错误"= 队列已经空了，它不会再自己动(见下面的 $drained 判定)
    $stallWarn = $null
    $timeout = [int]$S.runtime.arkTimeoutMinutes * 60
    $startTimeout = [int]$S.runtime.arkStartTimeoutMinutes * 60
    $stall = [int]$S.runtime.stallTimeoutMinutes * 60
    $idleConfirm = [int]$S.runtime.idleConfirmSeconds
    $arkName = [System.IO.Path]::GetFileNameWithoutExtension($S.paths.arknightsExe)
    $seenGame = [bool](Test-GdProcessRunning -Name $arkName)

    while ($true) {
        Start-Sleep -Seconds 10
        if (-not $seenGame -and (Test-GdProcessRunning -Name $arkName)) {
            $seenGame = $true
            Write-GdLog "端游客户端已被拉起来($arkName)"
        }
        $tail = Get-GdFileTail -Path $P.GuiLog -Offset $offset
        $offset = $tail.Offset
        if ($tail.Text) {
            $lastGrowth = Get-Date
            $seen += $tail.Text
            <# 批次 5：这段"每行是什么标志"的分类规则在 C#(parse-maa-gui-lines)，
               壳只把事件按行序回灌成本轮状态并打日志 —— 判定顺序/清洗/计数语义逐字对齐旧实现，
               改规则去改 Orchestration.cs 并跑 tools\panel-cs\build.ps1 -Verify(orchtest)。 #>
            $g = Invoke-GdCli -Verb 'parse-maa-gui-lines' -Body ([pscustomobject]@{
                text = $tail.Text
                benign = @($S.runtime.benignMaaErrors)
            })
            $markers += [int]$g.Markers
            $logChars += [int]$g.LogChars
            <# 批次 9：六档回灌的逐档语义(话术整句、chain 大小写不敏感累计、error 满 40 无声封顶、
               benign 按 Pattern 首见)已搬进 tools\panel-cs\RunLoops.cs(verb：apply-maa-gui-events)。
               壳只做三件事：喂事件+旧状态 → 日志按档重印 → 拿回执重建六个本地量。
               旧 switch 逐行 # 冻在下面 —— test-ark 的 `任务已完成，但出现错误`/`$drained = $true`
               字面锚就在冻结行里，别删别"顺手清理"。 #>
            $ge = Invoke-GdCli -Verb 'apply-maa-gui-events' -Body ([pscustomobject]@{
                events = @($g.Events)
                state  = [pscustomobject]@{
                    completed = $completed; errors = @($errors)
                    benignPatterns = @($benignSeen.Keys)
                    finished = [bool]$finished; drained = [bool]$drained; stallWarn = [string]$stallWarn
                }
            })
            foreach ($l in @($ge.Logs)) {
                $lvl = [string]$l.Level
                if ($lvl -and ($lvl -ne 'INFO')) { Write-GdLog ([string]$l.Text) -Level $lvl } else { Write-GdLog ([string]$l.Text) }
            }
            $completed = @{}
            if ($null -ne $ge.State.completed) {
                # 循环变量绝不能写 $p —— PowerShell 变量名不分大小写，$p 会踩掉 170 行的 $P(Get-MaaPaths)，
                # 下一 tick 380 行 `Test-GdProcessRunning -Name $P.Name` 就绑到空串抛出(2026-09-27 18:00/19:17
                # 两轮方舟第一拍即死的根因；benignPatterns 只要非空就触发，而 AutoStart 噪音每轮必在)。
                foreach ($cp in $ge.State.completed.PSObject.Properties) { $completed[[string]$cp.Name] = [int]$cp.Value }
            }
            $errors = @($ge.State.errors)
            $benignSeen = @{}
            foreach ($bp in @($ge.State.benignPatterns)) { $benignSeen[[string]$bp] = $true }
            $finished = [bool]$ge.State.finished
            $drained = [bool]$ge.State.drained
            $stallWarn = [string]$ge.State.stallWarn
            <# ----- 旧回灌段(批次 9 冻结，c498da0 原位备查)----- #>
            # foreach ($ev in @($g.Events)) {
            #     switch ([string]$ev.Kind) {
            #         'finished' {
            #             $finished = $true
            #             Write-GdLog "MAA 宣布任务全部完成$(if ($ev.Used) { "(内部计时 $($ev.Used))" })" -Level OK
            #         }
            #         'chain' {
            #             $chain = [string]$ev.Chain
            #             if (-not $completed.ContainsKey($chain)) { $completed[$chain] = 0 }
            #             $completed[$chain]++
            #             Write-GdLog "MAA 完成链路：$chain"
            #         }
            #         'stall' {
            #             $stallWarn = [string]$ev.Msg
            #             Write-GdLog "MAA 停滞告警：$stallWarn" -Level WARN
            #         }
            #         'drained' {
            #             <#
            #               MAA 把整条队列跑空了、但过程中有链路报错 —— 它不会自己再跑第二遍。
            #               这一句和「任务已全部完成」是两种收尾，早先只认后者，于是这种局要一直等到
            #               「asst.log 静默 22 分钟」才反应得过来(2026-09-25 07:53 那轮实测：6 条链路 0 完成，
            #               07:56:46 就打出这句，脚本却傻等到 08:19)。认下来，下面立刻处理。
            #               匹配字面"任务已完成，但出现错误"已搬进 Orchestration.cs 的 parse-maa-gui-lines，
            #               这里留原话给 t15 断言认锚 —— 改话术改 C#，别动这里的引文。
            #             #>
            #             $drained = $true
            #             Write-GdLog 'MAA 宣布本轮已跑完但有错误(队列已空，它不会再自己动)' -Level WARN
            #         }
            #         'error' {
            #             if ($errors.Count -lt 40) {
            #                 $errors += [string]$ev.Msg
            #                 Write-GdLog "MAA 异常线索：$($ev.Msg)" -Level WARN
            #             }
            #         }
            #         'benign' {
            #             # MAA 有几条 ERR 级前缀其实是正常噪音(实测随后链路照样完成)，别混进"异常线索"里
            #             if (-not $benignSeen.ContainsKey([string]$ev.Pattern)) {
            #                 $benignSeen[[string]$ev.Pattern] = $true
            #                 Write-GdLog "MAA 噪音(已按 benignMaaErrors 忽略)：$($ev.Msg)"
            #             }
            #         }
            #     }
            # }
        }

        <#
          asst.log 每轮也读一次，但**只取线索、不参与"日志有没有在动"的判定**：
          卡住时它照样在刷，拿它去重置 $lastGrowth 的话停滞永远测不出来。
          单次读到的量做个闸：MAA 的内核日志能涨到几十 MB，万一它被原地清空/轮转导致偏移失配，
          宁可跳过这一段，也不要一口气读进内存。
        #>
        try {
            if ($P.AsstLog -and (Test-Path -LiteralPath $P.AsstLog)) {
                $ai = Get-Item -LiteralPath $P.AsstLog
                if (($ai.Length - $asstOffset) -gt 4MB) {
                    $asstOffset = $ai.Length
                } elseif ($ai.Length -gt $asstOffset) {
                    $aTail = Get-GdFileTail -Path $P.AsstLog -Offset $asstOffset
                    $asstOffset = $aTail.Offset
                    if ($aTail.Text) {
                        <# 子任务重试次数才是"点了没动"的直接证据；inject 那个数只反映有没有滑基建，这里不参与判定。 #>
                        $st = Get-MaaAsstStuckState -Text $aTail.Text
                        $chanClicks += $st.Clicks
                        if ($st.Task) { $stuckTask = $st.Task; $stuckExec = $st.Exec }
                        $h = Get-MaaAsstStuckHint -Text $aTail.Text
                        if ($h) { $asstHint = $h }
                    }
                } else {
                    $asstOffset = $ai.Length   # 被原地清空/轮转过：跳到末尾，下一轮只读新增的
                }
            }
        } catch { $asstOffset = 0 }   # 读不动就当没这条线索，绝不影响本轮判定

        $elapsed = ((Get-Date) - $started).TotalSeconds
        $quiet = ((Get-Date) - $lastGrowth).TotalSeconds
        $doneCount = 0
        foreach ($k in $expectedCount.Keys) { $doneCount += [Math]::Min([int]$completed[$k], [int]$expectedCount[$k]) }
        $allDone = ($doneCount -ge $expectedCount.Values.Count) -and ($expectedCount.Count -gt 0)
        $chainText = (($completed.Keys | Sort-Object) -join ', ')
        $detail = "完成链路 $($doneCount)/$($expectedCount.Count)"
        if ($chainText) { $detail += "：$chainText" }
        if ($asstHint) { $detail += "；$asstHint" }
        if ($rescues.Count) { $detail += "；视觉兜底试过 $($rescues.Count) 次，最后一次：$($rescues[-1])" }

        if ($finished) { break }

        <#
          批次 7：十档判据梯(unknown-format / not-started / stuck / drained / stallWarn / timeout /
          quiet / 进程探活 / allDone 收尾)整体搬进了 tools\panel-cs\RunLoops.cs(verb：decide-maa-run-tick)，
          判据顺序、阈值比较、Detail 整句、兜底预算扣数、RecordTag 错位一格的唯一事实源在那边。
          下面这个迷你循环每 tick 只干三件事：把壳采好的读数喂给 verb → verb 挂回来的副作用(effect)
          当场执行、回执追加进 effectsResolved 后**同一 tick**重入续判(旧代码兜完当场决定 continue/return，
          隔一轮再判就不是逐字不变) → 出结论时按档位字面构造返回值。
          上面的 $elapsed/$quiet/$detail 自此只是"现场镜像"：给执行块的现场复核守卫用，
          兼作 test-ark 钉住的原文锚 —— 真正的判据不在这里。
        #>
        $st = $null
        $effx = @()          # 本 tick 已执行 effect 的回执(小写键：kind/detail/message/tried/done)
        $tailNow = $false    # verb 判到"该收尾"：出外层循环走挂钟收尾那三行
        while ($true) {
            $grabAgoSec = $null
            if ($null -ne $chanGrabAt) { $grabAgoSec = ((Get-Date) - $chanGrabAt).TotalSeconds }
            $d = Invoke-GdCli -Verb 'decide-maa-run-tick' -Body ([pscustomobject]@{
                now   = [pscustomobject]@{ elapsedSec = $elapsed; quietSec = $quiet; grabAgoSec = $grabAgoSec }
                live  = [pscustomobject]@{
                    maaRunning      = [bool](Test-GdProcessRunning -Name $P.Name)
                    rescueAvailable = [bool](Get-Command Invoke-GdVisionRescue -ErrorAction SilentlyContinue)
                    grabAvailable   = [bool](Get-Command Invoke-GdArkForegroundGrab -ErrorAction SilentlyContinue)
                }
                flags = [pscustomobject]@{
                    seenGame = [bool]$seenGame; markers = [int]$markers; logChars = [int]$logChars
                    finished = [bool]$finished; drained = [bool]$drained; stallWarn = [string]$stallWarn
                    completed = $completed; errors = @($errors); expectedChains = @($ExpectedChains)
                    asstHint = [string]$asstHint; stuckTask = [string]$stuckTask
                    stuckExec = [int]$stuckExec; chanClicks = [int]$chanClicks
                }
                cfg   = [pscustomobject]@{
                    startTimeoutSec = $startTimeout; timeoutSec = $timeout; stallSec = $stall
                    idleConfirmSec = $idleConfirm; startTimeoutMin = $S.runtime.arkStartTimeoutMinutes
                    timeoutMin = $S.runtime.arkTimeoutMinutes
                    abortOnMaaStallWarning = [bool]$S.runtime.abortOnMaaStallWarning
                    guiLogPath = [string]$P.GuiLog; rescueMaxRaw = [int]$rescueLeft
                }
                state = $st
                effectsResolved = @($effx)
            })
            $st = $d.State
            <# Directives：计时重置的下令时机在 C#(连"树上没有抢前台函数"那一档也要给 $chanGrabAt 打点 ——
               旧代码 $chanGrabAt = Get-Date 排在 Get-Command 检查之前，逐字如此)。 #>
            if ($d.Directives -and [bool]$d.Directives.GrabNow) { $chanGrabAt = Get-Date }
            if ($d.Directives -and [bool]$d.Directives.ResetLastGrowth) { $lastGrowth = Get-Date }
            if ($d.Directives -and [bool]$d.Directives.ClearStallWarn) { $stallWarn = $null }
            foreach ($l in @($d.Logs)) {
                $lvl = [string]$l.Level
                if ($lvl -and ($lvl -ne 'INFO')) { Write-GdLog ([string]$l.Text) -Level $lvl } else { Write-GdLog ([string]$l.Text) }
            }

            $ef = @($d.Effects)
            if ($ef.Count -eq 0) {
                <#
                  早退：Status/Detail/Errors 整句已由 C# 拼好，这里按档位逐档字面构造 ——
                  test-ark 钉的 `Status = 'unknown-format'` 就住在这一串 switch 分支里(批次 5 冻结块的交代)。
                #>
                if ($d.Action -eq 'return') {
                    switch ([string]$d.Status) {
                        'unknown-format' { return @{ Status = 'unknown-format'; Detail = [string]$d.Detail; Errors = @($d.Errors) } }
                        'not-started'    { return @{ Status = 'not-started'; Detail = [string]$d.Detail; Errors = @($d.Errors) } }
                        'timeout'        { return @{ Status = 'timeout'; Detail = [string]$d.Detail; Errors = @($d.Errors) } }
                        'stalled'        { return @{ Status = 'stalled'; Detail = [string]$d.Detail; Errors = @($d.Errors) } }
                        default          { return @{ Status = 'error'; Detail = [string]$d.Detail; Errors = @($d.Errors) } }
                    }
                }
                $tailNow = ($d.Action -eq 'tail')
                break
            }

            $e = $ef[0]
            $kind = [string]$e.Kind
            $did = $false

            <#
              ===== stuck 档执行块(点了没动)：原判据 `exec≥60 闸 + 链路 0 完成闸`、抢前台后 60 秒仍在原地
              整句早退、"抢完前台当场问一次画面"的早触发，全部在 RunLoops.cs 的 Ladder 第 4 档。
              下面原样保留的 if 只是"现场复核"守卫(读数本 tick 冻结，C# 挂了这档的 effect 它就成立)，
              test-ark 按这段里的调用点记"三笔账"、按 Grab→Rescue→Record 的落地顺序钉锚，别合并别删。
              两个闸的由来与"inject 数错点"那次错结论的教训，注释都在 RunLoops.cs/Processes.cs。
            #>
            if ($kind -eq 'grab' -or (([string]$e.Tag) -like 'stuck*')) {
                if (($stuckExec -ge 60) -and ($completed.Count -eq 0) -and (-not $finished)) {
                    if ($kind -eq 'grab') {
                        # 只有 grabAvailable=true 时 C# 才挂这一步；"树上没有抢前台的函数"那句走 C# 的自述分支
                        try { $effx += @{ kind = 'grab'; detail = [string](Invoke-GdArkForegroundGrab -S $S).Detail } }
                        catch { $effx += @{ kind = 'grab'; exception = $true; message = $_.Exception.Message } }
                        $did = $true
                    }
                    if ($kind -eq 'rescue') {
                        $rescueLeft = [int]$st.rescueLeft + 1   # 还原扣前值：预算扣数的事实源是 C# 的 state(挂 effect 时已扣)
                        if ($rescueLeft -gt 0 -and (Get-Command Invoke-GdVisionRescue -ErrorAction SilentlyContinue)) {
                            $rescueLeft--
                            $whyStuck = [string]$e.Context     # 原话是「自动化在同一个子任务[$stuckTask]上重复点了 $stuckExec 次，一条链路都没完成」—— WhyStuck() 拼串在 C#
                            $rc = $null
                            try { $rc = Invoke-GdVisionRescue -S $S -Tag ([string]$e.Tag) -Context $whyStuck }
                            catch { $rc = $null; $effx += @{ kind = 'rescue'; exception = $true; message = $_.Exception.Message } }
                            if ($null -ne $rc) { $effx += @{ kind = 'rescue'; tried = [bool]$rc.Tried; done = [bool]$rc.Done; detail = [string]$rc.Detail } }
                        }
                        $did = $true
                    }
                    if ($kind -eq 'record') {
                        $rc = [pscustomobject]@{ Tried = [bool]$e.Tried; Done = [bool]$e.Done; Detail = [string]$e.Detail }
                        $rescues += $rc.Detail       # 影子账本：只为下一 tick 开头的 $detail 镜像；结论话术的事实源是 C# 的 rescueNotes
                        Add-GdRescueRecord -S $S -Game 'ark' -Result $rc -Tag ([string]$e.Tag) -Target 'ark'
                        $effx += @{ kind = 'record' }
                        $did = $true
                    }
                }
            }
            <#
              ===== drain 档执行块(队列跑空)：2026-09-25 07:53 那轮的教训 —— 07:56 就宣布"跑完但有错误"、
              6 条链路 0 完成，老代码却傻等到"静默 22 分钟"才反应。这一路排在静默判定之前(顺序错了等于没改)，
              只做两件被证据撑住的事：当场兜底一次 + 立刻早退。这一轮不做原地重启：关端游重开 + 重起 MAA
              是外层那一次重试的事(08:4x 实测走的就是那条路)，所以这一段不写任何进程起停代码。
            #>
            if (([string]$e.Tag) -like 'drain*') {
                if ($drained -and -not $allDone) {
                    <#
                      "跑空但没跑齐"的判据与整句结论都在 C#(DrainSentence)，旧代码兜底后在此处直接
                          return @{ Status = 'stalled'; Detail = "…外层会重试一次…$detail"; Errors = $errors }
                      —— 兜过没兜成都早退。test-ark 钉着这一段的锚(`Status = 'stalled'`、"外层会重试一次"、
                      兜底调用点)由下面的现场复核与真调保留，别"顺手搬走"。
                    #>
                    if ($kind -eq 'rescue') {
                        $rescueLeft = [int]$st.rescueLeft + 1
                        if ($rescueLeft -gt 0 -and (Get-Command Invoke-GdVisionRescue -ErrorAction SilentlyContinue)) {
                            $rescueLeft--
                            $whyDrain = [string]$e.Context   # 原话是「MAA 自己说这一轮跑完了但报错，只完成 $doneCount/$($expectedCount.Count) 条链路，它不会再自己动」—— 拼串在 C#
                            $rc = $null
                            try { $rc = Invoke-GdVisionRescue -S $S -Tag ([string]$e.Tag) -Context $whyDrain }
                            catch { $rc = $null; $effx += @{ kind = 'rescue'; exception = $true; message = $_.Exception.Message } }
                            if ($null -ne $rc) { $effx += @{ kind = 'rescue'; tried = [bool]$rc.Tried; done = [bool]$rc.Done; detail = [string]$rc.Detail } }
                        }
                        $did = $true
                    }
                    if ($kind -eq 'record') {
                        $rc = [pscustomobject]@{ Tried = [bool]$e.Tried; Done = [bool]$e.Done; Detail = [string]$e.Detail }
                        $rescues += $rc.Detail
                        Add-GdRescueRecord -S $S -Game 'ark' -Result $rc -Tag ([string]$e.Tag) -Target 'ark'
                        $effx += @{ kind = 'record' }
                        $did = $true
                    }
                }
            }

            <#
              ===== quiet/stall 档执行块(日志静默过阈值)：旧代码先给视觉兜底一次机会再判 stalled
              (2026-09-24 中秋弹窗：人眼一看就该把挡路窗口关掉，模板匹配自己永远走不出来)。
              兜成 → 停滞计时从头算、也不让 $stallWarn 下一轮再把它提前判死 —— 旧代码那一句原地的
              continue 现在由"带回执重入 + Directives(ResetLastGrowth/ClearStallWarn)"等价替换；
              兜败或没有兜底 → 同一 tick 直接 stalled("$([int]($quiet/60)) 分钟无输出"整句在 C#)。
              这一档的调用 tag 在旧代码里就叫 stall(与档位名 quiet 不同词)，照抄。
            #>
            if (-not $did -and (([string]$e.Tag) -like 'stall*')) {
                if ($quiet -gt $stall) {
                    if ($kind -eq 'rescue') {
                        $rescueLeft = [int]$st.rescueLeft + 1
                        if ($rescueLeft -gt 0 -and (Get-Command Invoke-GdVisionRescue -ErrorAction SilentlyContinue)) {
                            $rescueLeft--
                            $rc = $null
                            try { $rc = Invoke-GdVisionRescue -S $S -Tag ([string]$e.Tag) }
                            catch { $rc = $null; $effx += @{ kind = 'rescue'; exception = $true; message = $_.Exception.Message } }
                            if ($null -ne $rc) { $effx += @{ kind = 'rescue'; tried = [bool]$rc.Tried; done = [bool]$rc.Done; detail = [string]$rc.Detail } }
                        }
                        $did = $true
                    }
                    if ($kind -eq 'record') {
                        $rc = [pscustomobject]@{ Tried = [bool]$e.Tried; Done = [bool]$e.Done; Detail = [string]$e.Detail }
                        $rescues += $rc.Detail
                        Add-GdRescueRecord -S $S -Game 'ark' -Result $rc -Tag ([string]$e.Tag) -Target 'ark'
                        $effx += @{ kind = 'record' }
                        $did = $true
                    }
                }
            }
            if (-not $did) {
                <# 判据挂了 effect 可哪个执行块都没接手(读数本 tick 冻结，理论上到不了这里)：
                   宁可作废这一 tick，也不能拿着没回执的挂起点空转 —— 下一 tick 的新读数会重新定档。 #>
                Write-GdLog "MAA tick：effect(kind=$kind，tag=$([string]$e.Tag))没有落到执行块，本 tick 作废(下一轮按新读数重判)" -Level WARN
                break
            }
        }
        <# loop：没结论，出迷你循环，外层 sleep 10 后进下一 tick。
           tail：出外层循环走挂钟收尾(重取一次 Get-Date 算时长 —— 那是"活"，逐字留在下面三行)。 #>
        if ($tailNow) { break }
    }

    <# 批次 9：挂钟收尾的拼串/数字形(Round(dur/60,1) 的 ToEven 与整数形、"完成链路："前缀)搬进
       RunLoops.cs(verb：finish-maa-run)。$dur 与排序链表仍是壳的现场量，算好喂进去。
       旧三行里的两行逐行 # 冻在下面。 #>
    $dur = ((Get-Date) - $started).TotalSeconds
    $chainText = (($completed.Keys | Sort-Object) -join ', ')
    $fin = Invoke-GdCli -Verb 'finish-maa-run' -Body ([pscustomobject]@{ durSec = $dur; chainText = $chainText })
    foreach ($l in @($fin.Logs)) { Write-GdLog ([string]$l.Text) -Level ([string]$l.Level) }
    return @{ Status = [string]$fin.Status; Detail = [string]$fin.Detail; Duration = [double]$fin.Duration; Errors = $errors }
    # ----- 旧挂钟收尾(批次 9 冻结，c498da0 原位备查)-----
    # Write-GdLog "MAA 日常链路完成，用时 $([math]::Round($dur/60,1)) 分钟" -Level OK
    # return @{ Status = 'ok'; Detail = "完成链路：$(($completed.Keys | Sort-Object) -join ', ')"; Duration = $dur; Errors = $errors }
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
