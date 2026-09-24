# lib/ark-decisions.ps1 — 方舟(端游 + MAA)侧"今天刷什么"的判定：活动窗口、确认门、领空回落、关卡校验
# 依赖 lib/common.ps1 + lib/decisions-common.ps1；只读判定，不启动任何程序。

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
    <# 校验关卡代号是否被 MAA 认识；返回 @{ Bad=@(...); Costs='30+30 理智' } #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)][string]$StageText)
    $table = Get-GdStageTable -S $S
    $list = @($StageText -split '[,，、;；\s]+' | Where-Object { $_ })
    $bad = @($list | Where-Object { -not $table.ContainsKey($_) })
    $cost = 0
    foreach ($s in $list) { if ($table.ContainsKey($s)) { $cost += [int]$table[$s] } }
    return [pscustomobject]@{
        Stages = $list
        Bad    = $bad
        Cost   = $cost
        Note   = if ($table.Count -eq 0) { '拿不到 MAA 关卡表，未校验' }
                elseif ($bad.Count) { "未知关卡：$($bad -join ', ')" }
                else { "共 $($list.Count) 关，单圈理智 $cost" }
    }
}

function Resolve-ArkPlan {
    <#
      纯判定：活动数据 + 当前时间 -> 方舟方案(不联网、不写盘，可被自检脚本喂假数据)
      返回 Mode = idle | event | event-pending
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
    $idlePlan = Get-GdMapValue $S.ark.planByWeekday "$dow"
    if (-not $idlePlan) { $idlePlan = $S.ark.defaultStage }

    $fightable = @()
    $server = Get-GdMapValue $Data 'Official'
    if ($server) {
        foreach ($grp in $server.PSObject.Properties) {
            $gv = $grp.Value
            if ($null -eq $gv) { continue }
            $entries = @()
            if ($gv -is [System.Array]) {
                $i = 0
                foreach ($item in $gv) { $entries += , @("item$i", $item); $i++ }
            } else {
                foreach ($item in $gv.PSObject.Properties) { $entries += , @($item.Name, $item.Value) }
            }
            foreach ($e in $entries) {
                $id = $e[0]; $v = $e[1]
                if ($null -eq $v) { continue }
                $act = Get-GdMapValue $v 'Activity'
                if ($null -eq $act) { $act = $v }
                $start = Convert-GdUtc8ToMs (Get-GdMapValue $act 'UtcStartTime')
                $end   = Convert-GdUtc8ToMs (Get-GdMapValue $act 'UtcExpireTime')
                if (-not $start -or -not $end) { continue }
                if ($Now -lt $start -or $Now -gt $end) { continue }
                $stages = @()
                $raw = Get-GdMapValue $v 'Stages'
                if ($raw) {
                    foreach ($st in $raw) {
                        $val = Get-GdMapValue $st 'Value'
                        if ($val) { $stages += [pscustomobject]@{ Value = [string]$val; Drop = [string](Get-GdMapValue $st 'Drop') } }
                    }
                }
                $fightable += [pscustomobject]@{
                    Group = $grp.Name; Id = [string]$id; Tip = [string](Get-GdMapValue $act 'Tip')
                    Start = $start; End = $end; Stages = $stages
                }
            }
        }
    }
    $fightable = @($fightable | Where-Object { $_.Stages.Count -gt 0 } | Sort-Object End)

    # 「资源收集」= 材料加倍期(没有活动代币，长草计划本身最优)，只作为提示
    $rcNote = ''
    $rc = Get-GdMapValue $server 'resourceCollection'
    if ($rc) {
        $rs = Convert-GdUtc8ToMs (Get-GdMapValue $rc 'UtcStartTime')
        $re = Convert-GdUtc8ToMs (Get-GdMapValue $rc 'UtcExpireTime')
        if ($rs -and $re -and $Now -ge $rs -and $Now -le $re) {
            $rcNote = "；正逢[$(Get-GdMapValue $rc 'Tip')]材料加倍期(至 $(Format-GdUnixMs $re))，刷材料本效率翻倍"
        }
    }

    $idle = {
        param($Reason, $Key = $null, $Tip = $null, $Done = $false)
        [pscustomobject]@{
            Mode = 'idle'; Stage = [string]$idlePlan; StageHint = $null; ClearSanity = $true
            Reason = "$Reason(数据源：$Source)$rcNote"; EventKey = $Key; EventTip = $Tip
            Source = $Source; ShopDone = $Done
        }
    }

    if ($fightable.Count -eq 0) {
        return (& $idle "无可刷活动关卡，按长草计划刷 $idlePlan")
    }

    # 商店已领空的活动：直接跳过，不再烧活动代币
    $shopDone = @{}
    if (-not $IgnoreShopDone -and (Test-GdShopDoneEnabled -S $S -Game 'ark')) {
        $shopDone = Get-GdShopDoneMap -Game 'ark'
    }
    $emptied = @($fightable | Where-Object { $shopDone.ContainsKey($_.Id) })
    $runnable = @($fightable | Where-Object { -not $shopDone.ContainsKey($_.Id) })

    if ($runnable.Count -eq 0) {
        $tips = (@($emptied | ForEach-Object { $_.Tip }) -join '、')
        return (& $idle "活动[$tips]商店已标记领空 → 剩余理智改刷长草计划 $idlePlan(要恢复刷活动：daily-clear.ps1 $(Get-GdEntryVerb -Game ark -Verb ShopReset))" `
                ([string]$emptied[0].Id) ([string]$emptied[0].Tip) $true)
    }

    $ev = $runnable[0]
    $pick = @($ev.Stages | Where-Object { $_.Drop -match '^\d{3,6}$' } | Select-Object -First 1)
    if ($pick.Count -eq 0) { $pick = @($ev.Stages | Select-Object -First 1) }
    $stage = [string]$pick[0].Value
    $ack = Get-GdAckMap -Game 'ark'
    $acked = $ack.ContainsKey($ev.Id)

    if ($S.ark.eventRequiresAck -and -not $acked) {
        $tail = if ($emptied.Count) { "；另有 $($emptied.Count) 个活动已标记领空" } else { '' }
        return [pscustomobject]@{
            Mode = 'event-pending'; Stage = [string]$idlePlan; StageHint = $stage; ClearSanity = $false
            Reason = "活动[$($ev.Tip)]($($ev.Group)/$($ev.Id)，至 $(Format-GdUnixMs $ev.End)) 进行中但你还没确认可自动刷 → 本轮不消耗理智。确认后运行 daily-clear.ps1 $(Get-GdEntryVerb -Game ark -Verb Ack)$tail"
            EventKey = $ev.Id; EventTip = $ev.Tip; Source = $Source; ShopDone = $false
        }
    }
    $skipNote = if ($emptied.Count) { "；另有 $($emptied.Count) 个活动商店已领空，已跳过" } else { '' }
    return [pscustomobject]@{
        Mode = 'event'; Stage = $stage; StageHint = $stage; ClearSanity = $true
        Reason = "活动[$($ev.Tip)]已确认自动刷 → 理智全刷 $stage($(Format-GdUnixMs $ev.Start) ~ $(Format-GdUnixMs $ev.End))$skipNote"
        EventKey = $ev.Id; EventTip = $ev.Tip; Source = $Source; ShopDone = $false
    }
}

function Get-ArkEvent {
    <# 取活动数据(接口 -> MAA 本地缓存 -> 无)后交给 Resolve-ArkPlan #>
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
