# lib/ark-decisions.ps1 — 方舟(端游 + MAA)侧的取数层 + 关卡表 + PS→C# 转发壳
# 依赖 lib/common.ps1 + lib/decisions-common.ps1；只读判定，不启动任何助手程序。
#
# ── 冻结(2026-09-26，PS→C# 批次 1)────────────────────────────────────────────
# Resolve-ArkPlan / Test-GdStages 的**规则本体**已迁到 tools\panel-cs\Decisions.cs
# (verb：decide-ark / check-stages；契约见 docs\ps-migration-batch0.md)。
# 本文件留下的两个函数只是转发壳：负责把规则需要的**值**(settings 块、真实 dow、ack/领空 map、
# 入口 verb 名、关卡表)组装好送进 C#，再把信封 data 原样交回。⚠ 11-02 转接刀：上面那句"两个函数"从来不是名册——Test-GdStages 那枚壳本批出仓(门侧改指 check-stages 出口)，在场每枚都在表账挂号，这里不数枚数。
# 所以：改文案/改分支请改 C# 那份，判定面的取值断言在 tools\panel-cs\Decisions.SelfTest.cs(随 build.ps1 -Verify 的 --dectest 跑)，不要在这里加规则。⚠ 10-26 甲档第六刀摘掉那 45 档没有对面的场景；第八刀把屏保 14 档逐字搬进该自检并整件退役 `tools\probe-decisions-golden.ps1`(取证见 docs\rust-core-plan.md §11.141／§11.144)——那座门自此不存在，判定面只认 `--dectest`。
# 组装哪几个值是协议的一部分：dow 的"周日=7"换算、IgnoreShopDone 与 shopDoneStopsEvent 的取图逻辑、
# verb 名(会被 Set-GdEntryVerb 现场改) —— test-ark [t7] 依赖这些留在 PS 侧。⚠ 10-30 B-3②-d 刀① 改口：这枚第三项**自此不在协议里**——body 不再传 verbAck／verbShopReset 两枚键，上面 :8 那句列举的第三项与本行的"verb 名"同批作废；判定层文案里那三句"要恢复：daily-clear.ps1 <verb>"的指路从句一起摘(代价与去向见 docs\rust-core-plan.md §11.175)。按 §11.173 ⑦ 登记的方式**只追加不删**，本行前半的旧表述原文留着。⚠ 11-01 丙形真转接(§11.176 ⑥)：那枚现场覆盖件连同它盖的进程内表一起退役，verb 名自此由取名函数现问模块注册表得到(问不到回落短名)，"会被现场改"这个说法自此只作历史所指。
# ──────────────────────────────────────────────────────────────────────────────

function Get-GdStageTable {
    <# 从 MAA 自带 resource/stages.json 建立 关卡代号 -> 理智消耗 的表(进程内缓存) #>
    param([Parameter(Mandatory)]$S)
    if ($global:GdStageTable) { return $global:GdStageTable }
    $table = @{}
    $path = Join-GdPath $S.paths.maaDir @('resource', 'stages.json')
    # Test-GdPathReady 而不是 Test-Path：maaDir 没填时 $path 是空串，别让它变成一句绑定错误
    if (Test-GdPathReady $path) {
        try {
            $j = Read-GdJson -Path $path
            # 新版 MAA 是数组 [{code,apCost,...}]，老版本可能是对象 -> 两种都吃
            $items = @()
            if ($j -isnot [pscustomobject]) { $items = @($j) }
            if (@($items).Count -eq 0) { $items = @($j.PSObject.Properties | ForEach-Object { $_.Value }) }
            foreach ($e in $items) {
                $code = [string]$e.code
                if (-not $code -or $code -eq 'System.Object[]') { continue }
                $cost = 0
                [void][int]::TryParse([string]$e.apCost, [ref]$cost)
                $table[$code] = $cost
            }
        } catch { Write-GdLog "stages.json 解析失败：$($_.Exception.Message)" -Level WARN }
    }
    if ($table.Count -eq 0) { Write-GdLog '未能建立 MAA 关卡表，理智计划不会被校验' -Level WARN }
    $global:GdStageTable = $table
    return $table
}

function Resolve-ArkPlan {
    <#
      转发壳：活动窗口/确认门/领空回落/文案的全部规则在 C#(decide-ark)。
      这里只组装规则要用的值 —— 真实时钟的 dow(周日按 7，老行为原样保留)。
      ⚠ 刀⑯ 笔(d)-1(2026-11-06)改口：旧组值三枚读件(Get-GdAckMap／Get-GdShopDoneMap／Get-GdArkEventProbe)
      与领空 flag 尺 Test-GdShopDoneEnabled 本批出仓，改指核 read-decision-state **一次**取齐(Ack／ShopDone／
      ShopDoneGateOpen／Probe 四格)；"给不给领空图"的折算原在本壳两行，刀㉑ 笔(b)-1(2026-11-08)起进核：本壳只传
      可选入键 ignoreShopDone(折图真身＝Round.FlagEnabled：缺省即开启、显式写 false 才关)，IgnoreShopDone 语义不变。settings 只喂本路那一块
      (真身 BlockOf 按 game 现问块名，喂全量与喂本块同一读数)。返回信封 data(PSCustomObject，属性名与
      顺序和旧版逐字一致)。
    #>
    param(
        [Parameter(Mandatory)]$S,
        $Data,
        [string]$Source = '无数据',
        [Parameter(Mandatory)][long]$Now,
        [switch]$IgnoreShopDone
    )
    $ci = Invoke-GdCli -Verb 'compose-decision-inputs' -Body ([pscustomobject]@{
        game = 'ark'
        settings = [pscustomobject]@{ ark = $S.ark }
        ignoreShopDone = [bool]$IgnoreShopDone
    })
    $body = [pscustomobject]@{
        ark = $S.ark
        dow = $ci.Dow
        now = $Now
        data = $Data
        source = $Source
        ack = $ci.Ack
        shopDone = $ci.ShopDone
        probe = $ci.Probe
    }
    return Invoke-GdCli -Verb 'decide-ark' -Body $body
}

# ⚠ 刀⑯ 收官批 笔(b)(2026-11-06)：Get-ArkEvent 整枚出仓(37 行，取证 raw\k35a-cut16-fin-recon.txt)——
#   取数三档(接口→MAA 本地缓存→无)与两句 WARN 原话全在核 verb read-ark-activity(Round.Data.cs::ArkActivity，
#   信封 Data/Source/CacheAgeHours/CacheStale/ApiUrlGiven/Offline/Lines，Lines 全 WARN 裸话术串)，
#   Round.SelfTest.cs 三档顺序档在位。消费方(ark-module StatusPlan／test-ark [t5])各自组装：
#   Get-GdNowMs 现场时钟(不许动§9-2) + read-ark-activity + Lines 逐条回放 + Resolve-ArkPlan 转发壳。

# ===== 每轮自证活动图(2026-10-12 第 1 刀) =====
# 需求原话(用户)：「活动要打，需要打通活动」「直接用尝试用 maa 进入活动最后一关，如果通了就说明通关了」。
# 于是把 -AckArk 那道人肉确认门换成机器自证：每轮拿活动最后一关当探针递下去，跑完从同一批现场读数
# (observe-maa-stage-open 那份)判"进得去没进得去"，结论落 state\ark-event-probe.json，下一轮喂回判定层。
# 判据(名单里有没有这一关)与"结论不落地"那三种无效形状全住在 C#(decide-ark-event-probe)，壳只管读盘写盘。
# ⚠ 刀⑯ 笔(d)-1(2026-11-06)：读盘那一半(Get-GdArkEventProbe，核臂 read-decision-state＋PS 回落臂)本批出仓——
#   判定层的 probe 那一枚由 Resolve-ArkPlan 经 read-decision-state 直答取齐(ReadProbe 三形归一 null 的口径在核侧)；
#   这里原先只留路径一枚(门侧夹具写盘用)。⚠ 刀㉓ 笔(b) 第三子批第四刀(2026-11-08)：门侧夹具不再写盘(test-ark:121 史注自陈零消费者)，
#   Get-GdArkEventProbePath 全树现拍除该注释外零活调用⇒真身出仓；probe 键集(Date/EventKey/Stage/Entered/Evidence)的家在 Decisions.cs 与 read-decision-state。
