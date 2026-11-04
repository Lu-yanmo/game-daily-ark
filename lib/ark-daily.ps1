# lib/ark-daily.ps1 — 方舟这一路的"日常动作"：状态标记 / 方案判定 / dry-run 预览 / 真正跑一轮
#
# 2026-09-23 内部拆分：函数体是从 daily-clear.ps1 逐字搬来的，只有两处形式上必须改：
#   1) 原来靠脚本作用域闭包拿 $S，现在改成显式 -S 参数；
#   2) 原来直接写 $results['ark']，现在把结果 return 出去，由入口脚本决定往哪儿存。
# 公开命令行(-ArkShopDone / -ArkStage / -Force)仍然长在 daily-clear.ps1 里 ——
# 本文件只管"给定这件事就干什么"，不管"用户敲了什么参数"。
# 追加(2026-10-12 第 1 刀)：-AckArk 与 Set-GdArkAck 一并退场 —— 用户口径「活动要打，需要打通活动，
# 直接用尝试用 maa 进入活动最后一关，如果通了就说明通关了」⇒ 活动图改由每轮机器自证(见 ark-decisions.ps1
# 尾段那三枚函数)，人肉确认门不再存在。Get-GdAckMap/Set-GdAckKey 底座保留：1999 那一路共用同一套 ack 机制。
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
# tools\panel-cs\build.ps1 -Verify(orchtest) 对拍，不要在这里加规则。
# ──────────────────────────────────────────────────────────────────────────────
#
# ── 追加冻结(2026-09-27，PS→C# 批次 8)─────────────────────────────────────────
#  重试分流的判据(跳过清单 ∧ retryOnce 与两句文案)住在 tools\panel-cs\Orchestration.cs 的
#  decide-daily-retry(-Game ark 支)，链体的回放在 tools\rustcore\src\main.rs 的 ark_daily_chain。
#  PS 侧那条臂连同在原地逐行 # 前缀冻结的旧分流已随 10-24 刀③ 整段出仓，取证见 docs\rust-core-plan.md。
#  原来由 tools\test-ark.ps1 钉的 `Status -notin @(…)` 字面锚随臂改口到判据真正的家(Orchestration.cs 的
#  ark 支窗口)，行为对面原在 probe-arkdrive 的 retry-stalled 档，10-27 第十九刀起搬进 main.rs 的 --selftest 第 29 节(见 Start-GdArkDaily 上方那段)。
# ──────────────────────────────────────────────────────────────────────────────
#
# ── R3③ 换头(2026-10-06)─────────────────────────────────────────────────────────
#  本刀起调度器只剩**直连核内驱动档**那一臂：Invoke-GdArkDailyRust 起内置件 gdcore.exe 走换头重入
#  协议(驱动档 --drive-ark-daily：问-答-重放；动作集=main.rs 的 ark_daily_chain)。PS 回退臂
#  Invoke-GdArkDailyLegacy 连同其函数体已整段出仓——这是决定不是疏漏：判据一枚没动，内置件不在场就
#  当场抛错，不再有"拨关走原身"那条退路。接线点仍只此一处(ADR §5.4"多处接线=实际不可回滚")。
#  返回值仍是 hashtable @{Status;Detail;Duration?}，调用方无感；那把换头主闸已随 10-24 刀④ 出仓。
#  改协议先改 main.rs 再复拍在场的门(只剩 probe-connect：probe-arkrun 已随甲档第二十刀退役)与 --selftest(第 18／29／30 节咬这一路)，不要在这里加规则。
# ──────────────────────────────────────────────────────────────────────────────

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
    # 同核内 start-ark-client 的路径闸与窗口查找(旧 Start-GdArkClient 真身随转接刀·方舟拉起族出仓)：
    # 预览也要按进程名过滤，别让浏览器标签页冒充"端游窗口已存在"
    $arkName = if ($S.paths.arknightsExe) { [System.IO.Path]::GetFileNameWithoutExtension([string]$S.paths.arknightsExe) } else { $null }
    $win = Get-GdWindowByTitle -Pattern $pattern -ProcessName $arkName
    Write-GdLog ("  端游窗口：" + $(if ($win) { "已存在 [$($win.Name)#$($win.Id)] $($win.Title)" } else { "没有 → 会先启动 $($S.paths.arknightsExe) 再让 MAA 连" }))
}

# ===== R3③ 换头 → 单臂(2026-10-24 刀③)：PS 回退臂整段出仓 =====
# Invoke-GdArkDailyLegacy(连同批次 8 那两枚 # 前缀冻结的旧分流)已移出仓库——这是决定不是疏漏：
# 判据一枚没动，跳过清单与两句文案在 tools\panel-cs\Orchestration.cs 的 decide-daily-retry(-Game ark)，
# 链体的编排与重试落地在 tools\rustcore\src\main.rs 的 ark_daily_chain，逐字转写的基线仍取钉位 251bd3c
# 那份，删前最后一帧的原身在钉位 5bc83b1 的 lib\ark-daily.ps1 里(那一帧本文件的 blob 一字未改)。
# 行为对面(10-27 甲档第十九刀改的家)：tools\rustcore\src\main.rs 的 --selftest 第 29 节——retry-stalled／desk-empty
# 两档的两格判据(C-retry-relaunch／C-desk-empty-vs-early)逐格搬进核内会话桌，probe-arkdrive 门随即整件退役。

function Start-GdArkDaily {
    <# 单臂调度器：直接走核内驱动档 executor；返回值形同旧 hashtable @{Status;Detail;Duration?}，调用方无感。
       兜底臂已随 10-24 刀③ 出仓，没有 PS 退路——内置件不在场时 Get-GdArkDriveExe 交回空串，由
       Invoke-GdArkDailyRust 那侧当场抛错。那把换头主闸 Test-GdRustDailyPath 本体已随本批 刀④ 出仓。 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision)
    return Invoke-GdArkDailyRust -S $S -Decision $Decision
}

function Get-GdArkDriveExe {
    <# 内置件 gdcore.exe 的候选序：出货树形态(tools\rustcore\gdcore.exe，重打 exe 后随包走) →
       cargo 形态(tools\rustcore\target\release\gdcore.exe，开发树直跑)。两者都不在返回 ''，
       由调用方按"没有就当场报错"处理 —— 本臂自 10-24 刀③ 起是唯一路，不再"默认档永不触"。 #>
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
       写的账落在这里；那三枚 ask 连同白名单 token 已于 10-25 甲档刀② 双删，新核不再问它们)。
       本函数**不自己造日志**：链上日志全部由 gdcore 侧产生，这里只照原级别回放 ——
       两门对拍靠的正是"回放串与旧侧逐字一致"，这里多打一行就红。
       B-2c② 换了通道：日志不再攒在信封里等收尾(信封 logs 键留而不删、恒为空)，而是按产生顺序
       逐行落进 --log-sink 指的侧信道文件，这里边跑边按字节偏移增量排空再回放。时序没变(动作仍在
       子进程退出、日志落完之后才执行)，变的只是落点；「留键不删键、恒空数组」这一形现由 main.rs 自检的信封 logs 格钉(原 arkdrive 门 C-logs 面已随第十九刀退役)。
       B-2c③ 起 run 也不再 ask：Invoke-MaaRun 那整段循环在核内真做(RealHost 走 --maa-run 同一套骨架)，
       现场 13 枚参数随 ctx 的 maaRun 交进去(paths 六格＋runtime 六格＋benignMaaErrors，键名与
       config\settings.json 逐字同名)。**取键逐枚点名是硬约束**——$S.runtime 整块里住着视觉兜底的 API key，
       序列化进来等于把 key 递进核、递进 ctx/journal 两本会留盘的账。 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision)

    $exe = Get-GdArkDriveExe
    if (-not $exe) { throw 'R3③ 这一路只剩核内驱动档了，但找不到内置件 gdcore.exe —— 先跑 tools\rustcore\build.ps1(或重打 exe)再试(兜底臂已随 10-24 刀③ 出仓，没有 PS 退路)' }
    $panel = Get-GdCliExe

    # 一次日常 = 一本账：ctx 换了 journal 就不能复用(内核按 init 与 ctx 全等校验)，所以每次开头清场重起。
    $journal = Join-Path $global:GD.State 'rust-ark-daily-journal.ndjson'
    $ctxFile = Join-Path $global:GD.State 'rust-ark-daily-ctx.json'
    $resFile = Join-Path $global:GD.State 'rust-ark-daily-res.json'
    $sink = Join-Path $global:GD.State 'rust-ark-daily-log-sink.ndjson'
    foreach ($f in @($journal, $resFile, $sink)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    # 侧信道一本会话一个文件(跨轮累加、核侧只追加不截断)：偏移在这里归零，之后由 Read-GdSinkIncrement 按**字节**推进。
    # 一律用 long：[ref] 会记住初值的类型，这里留 int 以后写 long 会被往回截(偏移算错=同一句日志重放)。
    $sinkOffset = [long]0
    # B-2c③：run 换核内真做之后，现场那 13 枚参数得随 ctx 交进去（键名与 config\settings.json 逐字同名）。
    # **逐枚点名取键是硬约束**：$S.runtime 整块里住着视觉兜底的 API key，序列化进来就等于把 key 递进核、
    # 递进 journal/ctx 那两本会留盘的账。要什么取什么，多一枚都不许。
    # benignMaaErrors 用 List[string] 累加而不是 @($S.runtime.benignMaaErrors)：那枚键没填时
    # @($null) 会占成一条空串错误项；foreach 扫 $null 才是零次。
    $benignMaa = New-Object System.Collections.Generic.List[string]
    foreach ($bm in $S.runtime.benignMaaErrors) { $benignMaa.Add([string]$bm) }
    Write-GdJson -Path $ctxFile -Object ([pscustomobject]@{
        launch     = [bool]($S.runtime.launchArkFromHelper -ne $false)
        retry_once = [bool]$S.runtime.retryOnce
        decision   = $Decision
        maaRun     = [pscustomobject]@{
            paths = [pscustomobject]@{
                maaDir       = [string]$S.paths.maaDir
                maaExe       = [string]$S.paths.maaExe
                maaConfig    = [string]$S.paths.maaConfig
                maaGuiLog    = [string]$S.paths.maaGuiLog
                maaAsstLog   = [string]$S.paths.maaAsstLog
                arknightsExe = [string]$S.paths.arknightsExe
            }
            runtime = [pscustomobject]@{
                arkStartTimeoutMinutes = [int]$S.runtime.arkStartTimeoutMinutes
                arkTimeoutMinutes      = [int]$S.runtime.arkTimeoutMinutes
                stallTimeoutMinutes    = [int]$S.runtime.stallTimeoutMinutes
                idleConfirmSeconds     = [int]$S.runtime.idleConfirmSeconds
                abortOnMaaStallWarning = [bool]$S.runtime.abortOnMaaStallWarning
                visionMaxRescue        = [int]$S.runtime.visionMaxRescue
                benignMaaErrors        = $benignMaa
            }
        }
    })

    # 外层硬闸(10-20)：核自己不退出时，Start-GdNativeStreamed 旧写法是**无界**等待，壳会陪着睡到计划任务
    # PT3H 把整班硬砍(10-20 18:00 班实证：核睡在 panel-cs 那一跳的收流上 34 分钟，台账零行)。
    # 取"内层业务超时 + 15 分钟"：内层那 70 分钟是**判据**，核照它自己收尾并回 timeout 信封；外层这一格
    # 只负责"绝不陪葬"，所以必须比内层宽，否则外层抢先把正常判定杀了。settings 那枚键没填时兜底 70，
    # 不许兜底成 0(那等于 15 分钟就砍，比内层还短)。
    $hardMin = [int]$S.runtime.arkTimeoutMinutes
    if ($hardMin -le 0) { $hardMin = 70 }
    $hardMs = ($hardMin + 15) * 60000
    $round = 0
    while ($true) {
        $round += 1
        if ($round -gt 500) { throw "R3③ 换头驱动轮次超上限(疑似死循环)：journal=$journal" }
        # 信封落点每轮换新文件，防读到上一轮读数；写不下去时 gdcore 退 stdout 末行(内核侧既定纪律)
        $envFile = Join-Path ([System.IO.Path]::GetTempPath()) ("gd-ark-daily-env-" + [guid]::NewGuid().ToString('N') + ".json")
        try {
            # 边跑边排空侧信道：06:00 那一轮要跑二十多分钟，卡住时一行不印就等于没留证(旧侧是收尾一次性倒)。
            $cap = Start-GdNativeStreamed -Exe $exe -SinkPath $sink -SinkOffset ([ref]$sinkOffset) -Arguments @(
                '--drive-ark-daily', '--i-drive', '--journal', $journal, '--ctx', $ctxFile,
                '--res', $resFile, '--panel-cs', $panel, '--state', $global:GD.State,
                '--log-sink', $sink, '--out', $envFile
            ) -OnSinkRow {
                param($r)
                $lvl = [string]$r.Level
                $txt = [string]$r.Text
                if ($lvl -and ($lvl -ne 'INFO')) { Write-GdLog $txt -Level $lvl } else { Write-GdLog $txt }
            } -HardWaitMs $hardMs
            $envText = ''
            if ([int]$cap.StreamTimeouts -gt 0) {
                # 口径（10-16 #473 取证后定档）：这一格**每轮必现**，不是异常也不是回归 —— 持有那份管道写端的
                # 既不是 gdcore 自己(它已退)、也不是它起的 MAA(三条 Stdio::null 全在)，而是链体里点过的**外部常驻服务**
                # (adb server 一类被 fork 成常驻并继承发起方 stdio)；那进程不归我们创建，改 spawn 参数治不掉。
                # 真日志走 --log-sink、进度判据走 journal／协议文件，stdout 只是冗余兜底 ⇒ 级别降 INFO、
                # 每轮一行仍可查，不许让"放弃"长得像"没事"，也不许每轮拿 WARN 吓人(见 docs\rust-core-plan.md §11.61)。
                Write-GdLog "R3③ 换头：收流按有界等待放弃 $([int]$cap.StreamTimeouts) 路 stdout/stderr(外部常驻服务持写端，stdout 兜底那一路本轮不可用；真日志见 --log-sink)"
            }
            if ($cap.WaitTimedOut) {
                # 第三种病(10-20)：核**压根没退出**，被外层硬闸收尸 —— 与上面"已退但放弃收流"必须分两句(并成一句之后，
                # 现场看到 WARN 就分不出该查核的等待还是查常驻服务)。这一支往下必然走"没给出信封"那条 throw，
                # 台账因此有行：本闸的全部意义就是把"缺勤一天"换成"一段可归因的失败"。
                Write-GdLog "R3③ 换头：核 $([int]($hardMs / 1000))s 仍没退出，已按外层硬闸结束它(它是没答，不是答错) —— 这一段按失败记账" -Level WARN
            }
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
            # 链体日志已在上面边跑边从侧信道按原级别回放完毕(空/INFO 走默认档，与旧侧 decide 回放同形)。
            # 信封的 logs 键 B-2c② 起留键不删键、恒为空数组，这里不再读它 —— 再读一遍等于同一句日志打两遍。
            $kind = [string]$envelope.kind
            if ($kind -eq 'done') {
                $dr = $envelope.result
                $out = @{ Status = [string]$dr.status; Detail = [string]$dr.detail }
                if ($null -ne $dr.duration) { $out.Duration = $dr.duration }
                # 每轮自证活动图(第 1 刀，10-12)不在这里：采集住核内 daily_round_chain 的自证段(verb update-ark-event-probe；原共用的 Run 钩子已随 11-04 刀⑤ 出仓)，
                # 换头这一路拨开/拨关都照样只采一次；拨关(默认)时本函数整体不触。
                return $out
            }
            if ($kind -eq 'fail') { throw ([string]$envelope.error) }
            if ($kind -ne 'ask') { throw "R3③ 换头：信封 kind 不认识($kind) —— 协议两侧不同源？" }

            $seq = [int]$envelope.seq
            $act = [string]$envelope.action
            $prm = $envelope.params
            if ($act -notin @('desk', 'svdetail', 'takeover', 'cfg', 'entryverb', 'launch', 'stop', 'sleep', 'skip', 'ledger', 'obs')) {
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
                        # 现问两枚核内出口(read-screensaver-config ／ resolve-screensaver-verdict)：三枚 PS 壳
                        # (Get-GdScreensaverConfig／Who／Verdict)已随转接刀·屏保稳态族出仓，这一路是唯一事实源在核内。
                        # ⚠ Found:false 折成 cfg=null，读不到就说"判断不了"，不许冒充 none。
                        $svTxt = ''
                        try {
                            $sd = Invoke-GdCli -Verb 'read-screensaver-config' -Body ([pscustomobject]@{})
                            $svv = Invoke-GdCli -Verb 'resolve-screensaver-verdict' -Body ([pscustomobject]@{ cfg = $(if ($sd.Found) { $sd } else { $null }) })
                            if ($svv) { $svTxt = [string]$svv.Detail }
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
                    'launch' {
                        # 转接刀·方舟拉起族(11-03)：Start-GdArkClient／Wait-GdArkLauncherReady 两枚真身出仓，这一路自此
                        # 唯一事实源在核内 Chain.cs::StartArkClient(它把"等窗口＋暖身＋启动器更新页的循环与真点击"一并干完)。
                        # ⚠ 语义闸：只认 [bool]$d.Started —— Done 在"等到窗口但没进游戏"那一档照样是真，取错就把 10-11
                        # 那次「对着更新页把五个任务全跑错(14m23s)」的缺陷放回来。核内自检测不到 PS，这一格由 tools\test-ark.ps1 钉形状。
                        # ⚠ Body 传空块：核自己现场读 config\settings.json(与这里的 $S 同源)；不许把 $S 整块序列化进临时 JSON——
                        # 视觉兜底那把 key 与 webhook 那类本机专属值一旦落盘就不是"读配置"，是"抄配置"(本文件全文不许出现那枚键名，
                        # 它由 tools\test-ark.ps1 的「壳侧一个字都不碰视觉 API key」那一格按**整份文本**扫，注释也算命中)。
                        $d = Invoke-GdCli -Verb 'start-ark-client' -Body ([pscustomobject]@{})
                        # 话术回放：核内 Say 把档位只写进自己的 GdLog、Lines 里只有正文(Chain.cs:221-227 现读) ⇒ 这一路的 WARN/STEP/OK 自此统一落默认档。
                        foreach ($l in @($d.Lines)) { Write-GdLog ([string]$l) }
                        $data = [bool]$d.Started
                    }
                    # B-2c③：'run' case 与白名单里那枚一起删净(双删)——Invoke-MaaRun 已在核内真做(maa_run + RealHost)，
                    # 现场那 13 枚参数从 ctx 的 maaRun 取。桩面留一 case 就等于给"分派漏改"留后门：
                    # 真核不再 ask run，若两侧有一边漏改，这里会当成成功回执吞掉，双删才让它在白名单处当场抛。
                    'stop' {
                        # 转接刀·方舟拉起族(11-03)：Stop-MaaAndGame 真身出仓，这一路唯一事实源在核内
                        # Chain.cs::StopMaaAndGame(两档分开的开关 quitAssistantAfter／closeArknightsAfter 各自一把进程树收尾，
                        # 只有真关掉才吭那一句)。⚠ 回执形状：核给的 Done 恒真(两档都关着也叫做完)、进程数只进话术不进键，
                        # 而 ask 那一侧(fire 方 main.rs DriveFx::stop)本就 |d| () 不收数据 ⇒ $data 照旧恒真，契约没动。
                        # 话术回放同 'launch' 那格的账；差别只在核里那两句本来就是 INFO 档(Chain.cs:390/397 现读)，丢档位这一路没有差异。
                        $d = Invoke-GdCli -Verb 'stop-maa-and-game' -Body ([pscustomobject]@{})
                        foreach ($l in @($d.Lines)) { Write-GdLog ([string]$l) }
                        $data = $true
                    }
                    'sleep' { Start-Sleep -Seconds ([int]$prm); $data = $true }
                    'skip' {
                        $sv = Get-GdMaaFightSkip -S $S
                        if ($null -eq $sv) { $data = $null }
                        else {
                            # @() 包住是忠实编码：$null 成员照旧占位(与旧侧 @($null).Count=1 行为一致)
                            $data = [pscustomobject]@{ skipped = [bool]$sv.Skipped; plan = @($sv.Plan); evidence = @($sv.Evidence) }
                        }
                    }
                    # 10-25 甲档刀②：'mark'／'obsrec'／'admin' 三 case 连同白名单里那三枚 token 一起删净(双删，口径与
                    # 上面那条 'run' 一字同)——名单事实源原是 arkdrive 门的 $moved = mark/obsrec/admin/run；门已于
                    # 10-27 甲档第十九刀整件退役(a9dea09 帧逐字副本同批出仓，实录 docs\rust-core-plan.md)；「new 侧
                    # 一枚 ask 都不出」改由 main.rs 自检第 18、29 节的 ask 名册格钉，核内 drive_mark／drive_obsrec／
                    # drive_is_admin 早已真做(B-1a)。桩面留一 case 就等于给"分派漏改"留后门，双删才让它在白名单处当场抛。
                    # 被删的只是答臂：Test-GdAdmin 真身另有生产读者(install-task.ps1:40／menu.ps1:177／reschedule-daily.ps1:42／vision-ask.ps1:63)，一枚没动；
                    # 原来那第三枚读者 vision-rescue.ps1:328 随第二十刀刀③ 的编排摘件一起没了，账见 docs\rust-core-plan.md §11.164。
                    'ledger' { $data = [string](Update-GdArkFarmLedger -S $S) }
                    'obs' { $data = Get-GdMaaStageObservation -S $S }
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
