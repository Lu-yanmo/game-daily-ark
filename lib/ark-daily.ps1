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
#
# ── R3③ 换头(2026-10-06)─────────────────────────────────────────────────────────
# Start-GdArkDaily 从"整函数"变成**调度器**(文件尾)：开关(Test-GdRustDailyPath，住 common.ps1，
#  三把判据见 docs\r0-adrs.md §5.4)拨开 → Invoke-GdArkDailyRust 起内置件 gdcore.exe 走换头重入
#  协议(驱动档 --drive-ark-daily：问-答-重放；动作集=main.rs 的 ark_daily_chain)；拨关(默认) →
#  原身逐字保留为 Invoke-GdArkDailyLegacy，行为一字不变。接线点只此一处(ADR §5.4"多处接线=
#  实际不可回滚")；两分支返回值同形(hashtable @{Status;Detail;Duration?})，调用方无感。
#  改协议先改 main.rs 再复拍三门(arkskip/live/events)，不要在这里加规则。
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

# R3③ 换头(2026-10-06)：原身只改了函数名(Start-GdArkDaily → Invoke-GdArkDailyLegacy)，函数体一字未动；
# 新入口 Start-GdArkDaily 是文件尾的调度器(开关拨开走 Rust 驱动档，拨关走这里)。
function Invoke-GdArkDailyLegacy {
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
    <# ===== 认关止损(2026-09-28 新增，非冻结段；判定规则在 C# detect-maa-fight-skip) =====
       09-28 06:00 实测：我们写的 StagePlan 三关确实落了盘(MAA 开机 .bak 里 farm 参数都在)，
       但 MAA 加载时把当日不可选的关修剪出计划、剩下的也不开放 → 整条 Fight 跳过，随后照常宣布
       「任务已全部完成」→ 判定层拿到假 ok，理智白放。三步止损：
       认跳关(只押「关卡计划内没有当日开放的关卡」) → 剔掉补刷关重试一次(能保长草理智就保) →
       重试仍跳则认栽：记当日标记(state\ark-fight-skip-mark.json)，当天后续轮不再前置 farm 关空试。
       这一步在既有 decide-daily-retry 分流**之后**再判：ok 轮外层分流根本不会动，互不踩脚。 #>
    if ($r.Status -eq 'ok') {
        $skip = $null
        try { $skip = Get-GdMaaFightSkip -S $S } catch { Write-GdLog "认关检查没做起来：$($_.Exception.Message)(不影响本轮)" -Level WARN }
        if ($skip -and [bool]$skip.Skipped) {
            $farmPlanV = Get-GdMapValue $ark 'Farm'
            $farmStages = @(if ($farmPlanV) { foreach ($st in @(Get-GdMapValue $farmPlanV 'Stages')) { [string]$st } })
            $planTxt = if (@($skip.Plan).Count) { (@($skip.Plan) -join ',') } else { '空' }
            Write-GdLog "MAA 认库后本轮的关计划实况是[$planTxt]并判「关卡计划内没有当日开放的关卡」(证据：$(@($skip.Evidence) -join ' / ')) → 整条 Fight 被跳过，这个 ok 是假的" -Level WARN
            $leanStages = @(foreach ($st in ($ark.Stage -split '[,，、;；\s]+')) { if ($st -and ($farmStages -notcontains [string]$st)) { [string]$st } })
            $recovered = $false
            $giveUp = $false
            if ($farmStages.Count -gt 0 -and $leanStages.Count -gt 0) {
                Write-GdLog "剔掉补刷关($($farmStages -join ','))后还剩 $($leanStages -join ',') → 收尾后按纯长草计划重试一次(保长草理智)" -Level WARN
                Stop-MaaAndGame -S $S
                Start-Sleep -Seconds 25
                $lean = @{
                    Source = 'auto'; Mode = [string]$ark.Mode; Stage = ($leanStages -join ',')
                    ClearSanity = [bool]$ark.ClearSanity
                    EventKey = $ark.EventKey; EventTip = $ark.EventTip; StageHint = $ark.StageHint
                }
                $maaCfg2 = Set-MaaDailyConfig -S $S -Decision $lean -Apply
                $maaCfg2.Changes | ForEach-Object { Write-GdLog "  MAA(剔关重试)：$_" }
                $runLean = {
                    # 与 $run 同款：拉端游必须在体重试里，剔关重试同样是"关干净重开"的一轮。
                    if ($S.runtime.launchArkFromHelper -ne $false) {
                        if (-not (Start-GdArkClient -S $S)) { Write-GdLog '端游窗口没等到：MAA 大概会报"未找到窗口"，仍继续' -Level WARN }
                    }
                    Invoke-MaaRun -S $S -ExpectedChains $maaCfg2.ExpectedChains
                }
                $r2 = Invoke-GdStep -Name '方舟剔关重试' -Body $runLean
                $r = $r2
                $skip2 = $null
                try { $skip2 = Get-GdMaaFightSkip -S $S } catch { Write-GdLog "第二次认关检查没做起来：$($_.Exception.Message)" -Level WARN }
                if ($skip2 -and [bool]$skip2.Skipped) {
                    $giveUp = $true
                    Write-GdLog "剔关重试仍被 MAA 判全关(计划实况：$(if (@($skip2.Plan).Count) { (@($skip2.Plan) -join ',') } else { '空' })) → 今日理智关卡确认全关" -Level WARN
                } elseif ($r2.Status -eq 'ok') {
                    $recovered = $true
                    Write-GdLog "剔关重跑后 Fight 正常打了，长草理智保住 → 今天不记认栽标记" -Level OK
                } else {
                    Write-GdLog "剔关重试本轮以 $($r2.Status) 收场，说不死关卡开没开 → 不记认栽标记(明天照常)" -Level WARN
                }
            } else {
                $giveUp = $true
                Write-GdLog '本轮没有可剔的补刷关(或剔完计划就空了) → 直接认今日全关' -Level WARN
            }
            if ($giveUp) {
                $mk = Set-GdArkFightSkipMark -S $S -Stages @((($ark.Stage -split ',') | Where-Object { $_ })) -Reason 'MAA 判「关卡计划内没有当日开放的关卡」'
                Write-GdLog "已记今日认栽标记($($mk.Date))：当天后续轮不再前置补刷关；若游戏里确有当日开放的图，可 -FarmArk 专用轮指定开放关补刷(专用轮不吃这条防线)" -Level WARN
                $tailNote = 'Fight 被 MAA 判全关(认栽，已记当日标记)'
                if ($r.Detail) { $r.Detail = "$($r.Detail)；$tailNote" } else { $r.Detail = $tailNote }
            }
        }
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
    # B 档观测(#21，2026-10-05)：把本轮 MAA 的关卡开放读数抄进观测账本，供人攒满一周后看账成案
    # (planByWeekday 提案必须人工确认) —— 这段只读日志+写账，不改任何配置、不影响本轮结论。
    try {
        $obs = Get-GdMaaStageObservation -S $S
        $on = Update-GdArkStageObs -S $S -Obs $obs
        if ($on) { Write-GdLog "关卡开放观测已记账(账本现 $on 条)" -Level OK }
    } catch { Write-GdLog "关卡开放观测没做起来：$($_.Exception.Message)(不影响本轮)" -Level WARN }
    return $r
}

# ===== R3③ 换头(2026-10-06)：调度器 + Rust 驱动档 executor =====
# Start-GdArkDaily 从"整函数"变成**调度器**：开关(Test-GdRustDailyPath，住 common.ps1，
# 三把判据见 docs\r0-adrs.md §5.4)拨开 → Invoke-GdArkDailyRust 起内置件 gdcore.exe 走换头
# 重入协议(驱动档 --drive-ark-daily：问-答-重放)；拨关(默认) → 原身逐字保留为
# Invoke-GdArkDailyLegacy，行为一字不变。接线点只此一处(ADR §5.4)：改协议先改 main.rs
# 再复拍三门，不要在这里加规则。
function Start-GdArkDaily {
    <# 调度器：两分支返回值同形(hashtable @{Status;Detail;Duration?})，调用方无感 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision)
    if (Test-GdRustDailyPath -S $S) { return Invoke-GdArkDailyRust -S $S -Decision $Decision }
    return Invoke-GdArkDailyLegacy -S $S -Decision $Decision
}

function Get-GdArkDriveExe {
    <# 内置件 gdcore.exe 的候选序：出货树形态(tools\rustcore\gdcore.exe，重打 exe 后随包走) →
       cargo 形态(tools\rustcore\target\release\gdcore.exe，开发树直跑)。两者都不在返回 ''，
       由调用方按"没有就当场报错"处理 —— 这条只在开关拨开时才被点到，默认档永不触。 #>
    $cands = @(
        (Join-Path $global:GD.Root 'tools\rustcore\gdcore.exe'),
        (Join-Path $global:GD.Root 'tools\rustcore\target\release\gdcore.exe')
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    return ''
}

function Invoke-GdArkDailyRust {
    <# R3③ 换头执行器：把原身的同步逻辑换成一串"问-答-重放"——
       每一轮起一个 gdcore.exe：它从 journal 重放已办事项回到断点，把下一个要办的动作写成
       ask 信封(seq/action/params)退出；这里照单执行完，把结果写 res 回执，再起下一轮。
       动作集与旧链逐条对齐(main.rs 的 ark_daily_chain 是事实源；改它=改协议，复拍三门)。
       --state 指到生产同一处 state 目录(B-1a：mark/obsrec/admin 已搬核内进程内真做，
       写的账落在这里；switch 里那三 case 保留只作白名单完备与回退面，新核不再 ask 它们)。
       本函数**不打任何 Write-GdLog**：链上日志全部由 gdcore 侧收集、这里按原级别回放 ——
       两门对拍靠的正是"回放串与旧侧逐字一致"，这里多打一行就红。 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision)

    $exe = Get-GdArkDriveExe
    if (-not $exe) { throw 'R3③ 换头拨开了但找不到内置件 gdcore.exe —— 先跑 tools\rustcore\build.ps1(或重打 exe)再试' }
    $panel = Get-GdCliExe

    # 一次日常 = 一本账：ctx 换了 journal 就不能复用(内核按 init 与 ctx 全等校验)，所以每次开头清场重起。
    $journal = Join-Path $global:GD.State 'rust-ark-daily-journal.ndjson'
    $ctxFile = Join-Path $global:GD.State 'rust-ark-daily-ctx.json'
    $resFile = Join-Path $global:GD.State 'rust-ark-daily-res.json'
    foreach ($f in @($journal, $resFile)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    Write-GdJson -Path $ctxFile -Object ([pscustomobject]@{
        launch     = [bool]($S.runtime.launchArkFromHelper -ne $false)
        retry_once = [bool]$S.runtime.retryOnce
        decision   = $Decision
    })

    $round = 0
    while ($true) {
        $round += 1
        if ($round -gt 500) { throw "R3③ 换头驱动轮次超上限(疑似死循环)：journal=$journal" }
        # 信封落点每轮换新文件，防读到上一轮读数；写不下去时 gdcore 退 stdout 末行(内核侧既定纪律)
        $envFile = Join-Path ([System.IO.Path]::GetTempPath()) ("gd-ark-daily-env-" + [guid]::NewGuid().ToString('N') + ".json")
        try {
            $cap = Invoke-GdNativeCapture -Exe $exe -Arguments @(
                '--drive-ark-daily', '--i-drive', '--journal', $journal, '--ctx', $ctxFile,
                '--res', $resFile, '--panel-cs', $panel, '--state', $global:GD.State, '--out', $envFile
            )
            $envText = ''
            if (Test-Path -LiteralPath $envFile) { $envText = [System.IO.File]::ReadAllText($envFile) }
            else {
                foreach ($ln in @($cap.Lines)) { $t = ([string]$ln).TrimStart(); if ($t.StartsWith('{')) { $envText = $t } }
            }
            if (-not $envText) {
                throw "R3③ 换头：gdcore 没给出信封(rc=$($cap.ExitCode))；输出末三行：$((@($cap.Lines) | Select-Object -Last 3) -join ' / ')"
            }
            $envelope = $envText | ConvertFrom-Json
            if ([string]$envelope.role -ne 'R3-drive-ark-daily') {
                throw "R3③ 换头：信封 role 不对($($envelope.role)) —— 这枚 gdcore.exe 不是驱动档那件？"
            }
            $want = Get-GdRustContract
            if ([string]$envelope.contract -ne $want) {
                throw "R3③ 换头：gdcore 契约号($($envelope.contract))与壳侧期望($want)不一致 —— 先重跑 tools\rustcore\build.ps1 再拨开关"
            }
            # 链体日志按原级别回放(空/INFO 走默认档，与旧侧 decide 回放同形)。回放必须在动作执行之前：
            # 信封 N 的 logs = 上一动作执行完、链体跑到断点前的新区 —— 与旧侧 Write-GdLog 时序逐字对齐。
            foreach ($l in @($envelope.logs)) {
                $lvl = [string]$l.level
                $txt = [string]$l.text
                if ($lvl -and ($lvl -ne 'INFO')) { Write-GdLog $txt -Level $lvl } else { Write-GdLog $txt }
            }
            $kind = [string]$envelope.kind
            if ($kind -eq 'done') {
                $dr = $envelope.result
                $out = @{ Status = [string]$dr.status; Detail = [string]$dr.detail }
                if ($null -ne $dr.duration) { $out.Duration = $dr.duration }
                return $out
            }
            if ($kind -eq 'fail') { throw ([string]$envelope.error) }
            if ($kind -ne 'ask') { throw "R3③ 换头：信封 kind 不认识($kind) —— 协议两侧不同源？" }

            $seq = [int]$envelope.seq
            $act = [string]$envelope.action
            $prm = $envelope.params
            if ($act -notin @('desk', 'svdetail', 'takeover', 'cfg', 'entryverb', 'launch', 'run', 'stop', 'sleep', 'skip', 'mark', 'ledger', 'obs', 'obsrec', 'admin')) {
                # 白名单之外直接抛(绕开下面的动作 catch)：不认识的动作 = 协议不同源，不许被当成"动作失败"混过去
                throw "R3③ 换头：收到不认识的动作 '$act'(seq=$seq) —— 先改 main.rs 再改这里，不许放行"
            }
            $ok = $true
            $data = $null
            $err = $null
            try {
                switch ($act) {
                    'desk' { $data = [string](Get-GdInputDesktopName) }
                    'svdetail' {
                        # 旧侧为把"屏保当时装着什么"写进早退原因的那整段(try/catch 内部吞异常、恒返 string)
                        $svTxt = ''
                        try {
                            if (Get-Command Get-GdScreensaverVerdict -ErrorAction SilentlyContinue) {
                                $svv = Get-GdScreensaverVerdict -Cfg (Get-GdScreensaverConfig)
                                if ($svv) { $svTxt = [string]$svv.Detail }
                            }
                        } catch { $svTxt = '' }
                        $data = $svTxt
                    }
                    'takeover' {
                        $arkName = [System.IO.Path]::GetFileNameWithoutExtension($S.paths.arknightsExe)
                        Invoke-GdTakeover -S $S -Names @((Get-MaaPaths -S $S).Name, $arkName) -Label '方舟/MAA'
                        $data = $true
                    }
                    'cfg' {
                        if ([string]$prm.kind -eq 'lean') {
                            $lean = @{
                                Source = 'auto'; Mode = [string]$Decision.Mode; Stage = [string]$prm.stage
                                ClearSanity = [bool]$Decision.ClearSanity
                                EventKey = $Decision.EventKey; EventTip = $Decision.EventTip; StageHint = $Decision.StageHint
                            }
                            $c = Set-MaaDailyConfig -S $S -Decision $lean -Apply
                        } else {
                            $c = Set-MaaDailyConfig -S $S -Decision $Decision -Apply
                        }
                        $data = [pscustomobject]@{ changes = @($c.Changes); chains = @($c.ExpectedChains) }
                    }
                    'entryverb' { $data = [string](Get-GdEntryVerb -Game ([string]$prm.game) -Verb ([string]$prm.verb)) }
                    'launch' { $data = [bool](Start-GdArkClient -S $S) }
                    'run' {
                        $rr = Invoke-MaaRun -S $S -ExpectedChains @($prm)
                        $rd = [pscustomobject]@{ status = [string]$rr.Status; detail = [string]$rr.Detail }
                        if ($null -ne $rr.Duration) { $rd | Add-Member -NotePropertyName duration -NotePropertyValue $rr.Duration }
                        $data = $rd
                    }
                    'stop' { Stop-MaaAndGame -S $S; $data = $true }
                    'sleep' { Start-Sleep -Seconds ([int]$prm); $data = $true }
                    'skip' {
                        $sv = Get-GdMaaFightSkip -S $S
                        if ($null -eq $sv) { $data = $null }
                        else {
                            # @() 包住是忠实编码：$null 成员照旧占位(与旧侧 @($null).Count=1 行为一致)
                            $data = [pscustomobject]@{ skipped = [bool]$sv.Skipped; plan = @($sv.Plan); evidence = @($sv.Evidence) }
                        }
                    }
                    'mark' {
                        $mk = Set-GdArkFightSkipMark -S $S -Stages @($prm.stages) -Reason ([string]$prm.reason)
                        $data = [string]$mk.Date
                    }
                    'ledger' { $data = [string](Update-GdArkFarmLedger -S $S) }
                    'obs' { $data = Get-GdMaaStageObservation -S $S }
                    'obsrec' { $data = Update-GdArkStageObs -S $S -Obs $prm }
                    'admin' { $data = [bool](Test-GdAdmin) }
                }
            } catch {
                $ok = $false
                $err = $_.Exception.Message
            }
            # 回执形状是协议：ok 真不许带 err 键、假不许带 data 键(main.rs drive_merge_res 逐字校验)
            $rf = [ordered]@{ seq = $seq; action = $act; ok = $ok }
            if ($ok) { $rf.data = $data } else { $rf.err = $err }
            Write-GdJson -Path $resFile -Object $rf
        } finally {
            if (Test-Path -LiteralPath $envFile) { Remove-Item -LiteralPath $envFile -Force }
        }
    }
}
