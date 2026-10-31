# lib/ark-decisions.ps1 — 方舟(端游 + MAA)侧的取数层 + 关卡表 + PS→C# 转发壳
# 依赖 lib/common.ps1 + lib/decisions-common.ps1；只读判定，不启动任何助手程序。
#
# ── 冻结(2026-09-26，PS→C# 批次 1)────────────────────────────────────────────
# Resolve-ArkPlan / Test-GdStages 的**规则本体**已迁到 tools\panel-cs\Decisions.cs
# (verb：decide-ark / check-stages；契约见 docs\ps-migration-batch0.md)。
# 本文件留下的两个函数只是转发壳：负责把规则需要的**值**(settings 块、真实 dow、ack/领空 map、
# 入口 verb 名、关卡表)组装好送进 C#，再把信封 data 原样交回。
# 所以：改文案/改分支请改 C# 那份，判定面的取值断言在 tools\panel-cs\Decisions.SelfTest.cs(随 build.ps1 -Verify 的 --dectest 跑)，不要在这里加规则。⚠ 10-26 甲档第六刀摘掉那 45 档没有对面的场景；第八刀把屏保 14 档逐字搬进该自检并整件退役 `tools\probe-decisions-golden.ps1`(取证见 docs\rust-core-plan.md §11.141／§11.144)——那座门自此不存在，判定面只认 `--dectest`。
# 组装哪几个值是协议的一部分：dow 的"周日=7"换算、IgnoreShopDone 与 shopDoneStopsEvent 的取图逻辑、
# verb 名(会被 Set-GdEntryVerb 现场改) —— test-ark [t7] 依赖这些留在 PS 侧。⚠ 10-30 B-3②-d 刀① 改口：这枚第三项**自此不在协议里**——body 不再传 verbAck／verbShopReset 两枚键，上面 :8 那句列举的第三项与本行的"verb 名"同批作废；判定层文案里那三句"要恢复：daily-clear.ps1 <verb>"的指路从句一起摘(代价与去向见 docs\rust-core-plan.md §11.175)。按 §11.173 ⑦ 登记的方式**只追加不删**，本行前半的旧表述原文留着。
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

function Test-GdStages {
    <# 转发壳：拆分/查表/合计的规则在 C#(check-stages)；关卡表由上面的 Get-GdStageTable 读好后喂进去 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)][string]$StageText)
    $table = Get-GdStageTable -S $S
    return Invoke-GdCli -Verb 'check-stages' -Body ([pscustomobject]@{ table = $table; stageText = $StageText })
}

function Resolve-ArkPlan {
    <#
      转发壳：活动窗口/确认门/领空回落/文案的全部规则在 C#(decide-ark)。
      这里只组装规则要用的值 —— 真实时钟的 dow(周日按 7，老行为原样保留)、
      按 IgnoreShopDone + shopDoneStopsEvent 决定给不给领空图、现场 verb 名、ack 图。
      返回信封 data(PSCustomObject，属性名与顺序和旧版逐字一致)。
    #>
    param(
        [Parameter(Mandatory)]$S,
        $Data,
        [string]$Source = '无数据',
        [Parameter(Mandatory)][long]$Now,
        [switch]$IgnoreShopDone
    )
    $dow = [int](Get-Date).DayOfWeek
    if ($dow -eq 0) { $dow = 7 }
    $shopDone = @{}
    if (-not $IgnoreShopDone -and (Test-GdShopDoneEnabled -S $S -Game 'ark')) {
        $shopDone = Get-GdShopDoneMap -Game 'ark'
    }
    $body = [pscustomobject]@{
        ark = $S.ark
        dow = $dow
        now = $Now
        data = $Data
        source = $Source
        ack = (Get-GdAckMap -Game 'ark')
        shopDone = $shopDone
        probe = (Get-GdArkEventProbe)
    }
    return Invoke-GdCli -Verb 'decide-ark' -Body $body
}

function Get-ArkEvent {
    <# 取活动数据(接口 -> MAA 本地缓存 -> 无)后交给 Resolve-ArkPlan(现即转发壳) #>
    param([Parameter(Mandatory)]$S, [switch]$Offline, [switch]$IgnoreShopDone)

    $now = Get-GdNowMs
    $data = $null
    $source = ''

    if (-not $Offline -and $S.ark.activityApiUrl) {
        try {
            Enable-GdTls12   # 5.1 默认不发 TLS 1.2，这里不补一句的话活动接口在 5.1 下必然拉不到
            $resp = Invoke-WebRequest -Uri $S.ark.activityApiUrl -TimeoutSec 8 -UseBasicParsing
            $data = $resp.Content | ConvertFrom-Json
            $source = 'MAA 活动接口'
        } catch {
            Write-GdLog "活动接口拉取失败($($_.Exception.Message))，改用本地缓存" -Level WARN
        }
    }
    if (-not $data) {
        $cache = Join-GdPath $S.paths.maaDir @($S.paths.maaActivityCache)
        if (Test-Path -LiteralPath $cache) {
            $age = (New-TimeSpan -Start (Get-Item -LiteralPath $cache).LastWriteTime).TotalHours
            $data = Read-GdJson -Path $cache
            $source = "MAA 本地缓存($([math]::Round($age,1)) 小时前)"
            if ($age -gt [int]$S.ark.activityCacheMaxHours) {
                Write-GdLog "活动缓存超过 $($S.ark.activityCacheMaxHours) 小时未刷新，结论可能滞后(MAA 启动后会自行更新)" -Level WARN
            }
        } else {
            Write-GdLog "既拉不到活动接口、也没有本地缓存 → 按长草期处理" -Level WARN
            $source = '无数据'
        }
    }

    $a = @{ S = $S; Data = $data; Source = $source; Now = $now }
    if ($IgnoreShopDone) { $a['IgnoreShopDone'] = $true }
    return (Resolve-ArkPlan @a)
}

# ===== 每轮自证活动图(2026-10-12 第 1 刀) =====
# 需求原话(用户)：「活动要打，需要打通活动」「直接用尝试用 maa 进入活动最后一关，如果通了就说明通关了」。
# 于是把 -AckArk 那道人肉确认门换成机器自证：每轮拿活动最后一关当探针递下去，跑完从同一批现场读数
# (observe-maa-stage-open 那份)判"进得去没进得去"，结论落 state\ark-event-probe.json，下一轮喂回判定层。
# 判据(名单里有没有这一关)与"结论不落地"那三种无效形状全住在 C#(decide-ark-event-probe)，壳只管读盘写盘。
# 键集与 Decisions.cs 那侧的 probe 入参一一对上：Date / EventKey / Stage / Entered / Evidence。
function Get-GdArkEventProbePath { Join-Path $global:GD.State 'ark-event-probe.json' }

function Get-GdArkEventProbe {
    <# 只读：上一轮的活动图自证结论。文件不在/读坏了回 $null —— 判定层据此当"没探过"处理，
       照常拿最后一关当探针，绝不会因为采集失败就把活动图判成没打通(那才是真丢理智)。 #>
    $p = Get-GdArkEventProbePath
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { $m = Read-GdJson -Path $p } catch { return $null }
    if (-not $m -or -not [string]$m.EventKey) { return $null }
    return [pscustomobject]@{
        Date     = [string]$m.Date
        EventKey = [string]$m.EventKey
        Stage    = [string]$m.Stage
        Entered  = [bool]$m.Entered
        Evidence = [string]$m.Evidence
    }
}

function Update-GdArkEventProbe {
    <# 收尾采集：本轮下发过活动关(判定给得出 EventKey+StageHint)且有观测读数时，问一次
       decide-ark-event-probe，Valid 才落盘。这一步和认栽标记一样属于"活"，任何失败只 WARN 不影响本轮结论。 #>
    param([Parameter(Mandatory)]$S, $Decision, $Obs)
    if (-not $Decision -or -not [string]$Decision.EventKey) { return $null }
    $target = [string]$Decision.StageHint
    if (-not $target) { return $null }
    $d = Invoke-GdCli -Verb 'decide-ark-event-probe' -Body ([pscustomobject]@{
        date     = (Get-Date).ToString('yyyy-MM-dd')
        eventKey = [string]$Decision.EventKey
        stage    = $target
        obs      = $Obs
    })
    if (-not [bool]$d.Valid) {
        Write-GdLog "活动图自证：$([string]$d.Evidence)" -Level WARN
        return $null
    }
    $obj = [ordered]@{
        Date     = [string]$d.Date
        EventKey = [string]$d.EventKey
        Stage    = [string]$d.Stage
        Entered  = [bool]$d.Entered
        Evidence = [string]$d.Evidence
    }
    Write-GdJson -Path (Get-GdArkEventProbePath) -Object $obj
    if ($obj.Entered) {
        Write-GdLog "活动图自证：$($obj.Stage) 进得去 → 下一轮照常按活动图刷($($obj.Evidence))" -Level OK
    } else {
        Write-GdLog "活动图自证：$($obj.Stage) 进不去 → 判为还没打通，当日剩余轮改刷长草($($obj.Evidence))" -Level WARN
    }
    return $obj
}
