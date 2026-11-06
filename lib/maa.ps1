# lib/maa.ps1 — 配置并驱动 MAA(明日方舟端游 / Win32 控制器)
#
# ── 冻结(2026-09-26，PS→C# 批次 3；2026-10-27 随甲档第四刀刀②改口)──────────────
# 本体已迁到 tools\panel-cs\Processes.cs(契约见 docs\ps-migration-batch0.md)：
#   Get-MaaAsstStuckState → verb parse-asst-state(四个"当前状态"的抠法在 C#；inject 只反映滑基建的老教训也在那) ⚠ 11-02 转接刀：这枚壳已出仓，门侧改指 CLI 出口。
#   Get-MaaAsstStuckHint  → verb parse-asst-hint(线索话术整句在 C#) ⚠ 同批出仓；两句自此只剩来历陈述，别再当"本文件里还有这枚"读。
#   Set-MaaDailyConfig 的规则段 → verb plan-maa-queue(队列开关/关卡校验/farm 两档九项/ExpectedChains
#       的 Select-Object -Unique 大小写敏感去重，全部在 C#；本壳保留：在跑检查、读写盘、备份、回读核对、日志染色)
# 所以：改规则/文案请改 Processes.cs ⚠ 11-06 转接刀·运行面刀⑱：Set-MaaDailyConfig 这枚转发壳整枚出仓（现场检查/读写盘/回放/回读核对四段对面全在 Chain.cs::ApplyMaaDailyConfig，verb apply-maa-daily-config），门侧四处自此改问 CLI 出口。 并跑 panel-cs --proctest 对真值，不要在这里加规则。
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
