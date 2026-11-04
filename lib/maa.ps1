# lib/maa.ps1 — 配置并驱动 MAA(明日方舟端游 / Win32 控制器)
#
# ── 冻结(2026-09-26，PS→C# 批次 3；2026-10-27 随甲档第四刀刀②改口)──────────────
# 本体已迁到 tools\panel-cs\Processes.cs(契约见 docs\ps-migration-batch0.md)：
#   Get-MaaAsstStuckState → verb parse-asst-state(四个"当前状态"的抠法在 C#；inject 只反映滑基建的老教训也在那) ⚠ 11-02 转接刀：这枚壳已出仓，门侧改指 CLI 出口。
#   Get-MaaAsstStuckHint  → verb parse-asst-hint(线索话术整句在 C#) ⚠ 同批出仓；两句自此只剩来历陈述，别再当"本文件里还有这枚"读。
#   Set-MaaDailyConfig 的规则段 → verb plan-maa-queue(队列开关/关卡校验/farm 两档九项/ExpectedChains
#       的 Select-Object -Unique 大小写敏感去重，全部在 C#；本壳保留：在跑检查、读写盘、备份、回读核对、日志染色)
# 所以：改规则/文案请改 Processes.cs 并跑 panel-cs --proctest 对真值，不要在这里加规则。
# 现势：监控循环 Invoke-MaaRun(旧 :220-620)已整函数出仓——循环骨架在核内 maa_run<H: MaaHost>
# (tools\rustcore\src\main.rs，判据外调 C#，生产 = maa_run + RealHost)。⚠ 11-02 转接刀后这半句作废：
# 本文件剩下的是"读现场、改写队列"那几枚壳(⚠ 11-03 转接刀·方舟拉起族把"起进程、启动器页、进程树收尾"那几枚摘走，
# 这一路的唯一事实源在 tools\panel-cs\Chain.cs)，逐枚账在 tools\ps-map\ps-map.tsv，这里不点名。
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

# Get-GdMaaFightSkip 与 Get-GdMaaStageObservation 已删(11-05 转接刀·运行面刀⑨)：两枚都只剩"现场读盘半段"的壳，
# 判据一枚也不在这里重写——判定本体住 tools/panel-cs/Orchestration.cs(detect-maa-fight-skip／observe-maa-stage-open)，
# 读盘半段的对面住 Chain.cs::ReadFightSkip／::ReadStageObservation(verb read-maa-fight-skip／read-maa-stage-observation，
# Round.SelfTest 第 23／24 节有格，含 asst.log 尾 16MB 那扇窗)，表账档位词两枚皆「已承接」；
# 编排岛 11-04 刀⑦ 出仓后全仓 AST 零调用点(k853／k854／k855 三把尺同帧)。
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
