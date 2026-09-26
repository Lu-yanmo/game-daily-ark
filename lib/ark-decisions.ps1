# lib/ark-decisions.ps1 — 方舟(端游 + MAA)侧的取数层 + 关卡表 + PS→C# 转发壳
# 依赖 lib/common.ps1 + lib/decisions-common.ps1；只读判定，不启动任何助手程序。
#
# ── 冻结(2026-09-26，PS→C# 批次 1)────────────────────────────────────────────
# Resolve-ArkPlan / Test-GdStages 的**规则本体**已迁到 tools\panel-cs\Decisions.cs
# (verb：decide-ark / check-stages；契约见 docs\ps-migration-batch0.md)。
# 本文件留下的两个函数只是转发壳：负责把规则需要的**值**(settings 块、真实 dow、ack/领空 map、
# 入口 verb 名、关卡表)组装好送进 C#，再把信封 data 原样交回。
# 所以：改文案/改分支请改 C# 那份并跑 tools\probe-decisions-golden.ps1 对拍，不要在这里加规则。
# 组装哪几个值是协议的一部分：dow 的"周日=7"换算、IgnoreShopDone 与 shopDoneStopsEvent 的取图逻辑、
# verb 名(会被 Set-GdEntryVerb 现场改) —— test-ark [t7] 依赖这些留在 PS 侧。
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
        verbAck = (Get-GdEntryVerb -Game ark -Verb Ack)
        verbShopReset = (Get-GdEntryVerb -Game ark -Verb ShopReset)
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
