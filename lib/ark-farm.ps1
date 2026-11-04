# lib/ark-farm.ps1 — 方舟「智能刷材料」(对标 M9A 的智能均衡刷材料)：掉落记账 / 目标清单 / 缺口方案
#
# 和 1999 那一路的分工正好相反：M9A 的"智能"在助手自己肚子里(选关/吃糖/统计都是它的事，
# 工程只发"启动哪个实例")；MAA 虽然也有「指定材料刷到 N」的原生开关，但它的运行时语义
# (TargetDrop 到底按什么计数、TimesLimit 圈不圈整条队列)是二进制里的事，猜错就是白烧理智。
# 所以这一路的"脑子"放在工程里，且拆成两档：
#   顺带档(日常轮)  ：只把 farm 关拼进理智计划的尾部，止损靠理智本身，缺口逐日从掉落记账里减；
#   专用档(-FarmArk) ：整条 Fight 链只挂 farm 关，并打开 MAA 的 TargetDrop/TimesLimit 双保险 ——
#                     这两处就算语义判错，损失上限也只有"一轮理智"，不会失控。
# 库存的"绝对值"是拿不到的(gui.log 的掉落统计只有本次增量)，所以账本是自己记的：
# 首跑若有 MAA 的 DepotData 缓存就拿它标定一次初值(标成估算)，之后只按 (+N) 累加。
#
# 依赖：调用方先点 lib\common.ps1 + lib\ark-decisions.ps1(关卡校验) + lib\maa.ps1(Get-MaaPaths)。
# 纯函数(Parse-*/Resolve-ArkFarmPlan)不碰文件，给 tools\test-ark.ps1 喂假数据断言。
#
# ── 冻结(2026-09-27，PS→C# 批次 5)────────────────────────────────────────────
# Parse-GdArkFarmTargetSpec / Parse-GdArkDropText / Resolve-ArkFarmPlan 的**规则本体**
# 已迁到 tools\panel-cs\Orchestration.cs(verb：parse-farm-target-spec / parse-ark-drop-text /
# resolve-ark-farm-plan；契约见 docs\ps-migration-batch0.md)。本文件留下的这三个函数只是转发壳：
# 负责把规则需要的**值**(目标清单原始项、账本三张表、关卡校验表)组装好送进 C#，再把信封 data 交回。
# 所以：改判表/改文案请改 C# 那份并跑 tools\panel-cs\build.ps1 -Verify(orchtest)，不要在这里加规则。
# 留在 PS 侧的是活层：Get-GdArkItemMaps/Read-GdArkFarmLedger/Update-GdArkFarmLedger(文件 IO 与记账)、
# Sync-GdArkFarmHaveFromDepot(DepotData 纠偏)、Resolve-GdArkFarmDecision(farmAppend 开关与档位判定)、
# Get-GdArkFarmTargetsNormalized(循环壳) —— 起进程/读盘/写盘归编排层后续批次。
# ──────────────────────────────────────────────────────────────────────────────

function Get-GdArkFarmInventoryPath { Join-Path $global:GD.State 'ark-inventory.json' }
function Get-GdArkFarmDropTablePath { Join-Path $global:GD.State 'ark-droptable.json' }
function Get-GdArkFarmDropsPath    { Join-Path $global:GD.State 'ark-farm-drops.json' }
function Get-GdArkFightSkipMarkPath { Join-Path $global:GD.State 'ark-fight-skip-mark.json' }

# Set-GdArkFightSkipMark 已删(10-25 甲档刀②，docs\rust-core-plan.md §11.134)：lib\ark-daily.ps1 里那枚 'mark'
# 问槽与白名单 token 同批双删(口径同 B-2c③ 那条 'run')，核内等价体在 tools\rustcore\src\main.rs::drive_mark；
# probe-arkdrive 门的 old／new 两代自同批刀① 起只咬该门自带的 a9dea09 帧逐字副本 ⇒ 现树再无读者(门已于 10-27 第十九刀整件退役)。
# 写侧出仓、读侧照旧活：Test-GdArkFightSkipMarkToday 与 Get-GdArkFightSkipMarkPath 仍是 PS 轮读当天认栽标记那一路。

function Test-GdArkFightSkipMarkToday {
    <# 只读：今天是否已经认栽。文件不在/读坏了都答 $false —— 认栽防线宁可失效也不拦正常轮。 #>
    param([Parameter(Mandatory)]$S)
    $p = Get-GdArkFightSkipMarkPath
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $m = $null
    try { $m = Read-GdJson -Path $p } catch { return $false }
    return (([string]$m.Date) -eq (Get-Date).ToString('yyyy-MM-dd'))
}

# Get-GdArkStageObsPath 与 Update-GdArkStageObs 已删(10-25 甲档刀②，docs\rust-core-plan.md §11.134)：这两枚是
# 上面那枚 mark 的同族——lib\ark-daily.ps1 里 'obsrec' 问槽与白名单 token 同批双删，核内等价体在
# tools\rustcore\src\main.rs::drive_obsrec(账本路径字面、Found=false 不记、周一=1…周日=7、60 条滑窗与
# "读坏当空账"四样都在核内逐句照旧)；probe-arkdrive 门两代只咬它自带的 a9dea09 帧逐字副本 ⇒ 现树再无读者(门已于 10-27 第十九刀退役)。
# 同族的 'obs'(Get-GdMaaStageObservation，旧在 lib\maa.ps1；⚠ 11-05 转接刀·运行面刀⑨ 那枚壳已出仓，读盘半段的对面在 tools\panel-cs\Chain.cs::ReadStageObservation)那阵子没搬、问槽照旧活；state\ark-stage-weekday-obs.json 的写手自此只有核。

function Get-GdArkItemMaps {
    <# MAA 自带 resource/item_index.json → 材料名↔代号两张表(进程内缓存)。
       475 条覆盖常规材料，但装备模组那类新货币不在表里 —— 认不出来的材料由调用方明说，不猜。 #>
    param([Parameter(Mandatory)]$S)
    # 懒初始化：common.ps1 开着 StrictMode 1.0，直接读未声明的 $global:GdArkItemMaps 会当场报错(这一招在判定层也曾有一枚同名取表件，那枚已随 11-01 丙形真转接退役)
    if (Get-Variable -Name GdArkItemMaps -Scope Global -ErrorAction SilentlyContinue) { return $global:GdArkItemMaps }
    $n2i = @{}; $i2n = @{}
    $path = Join-GdPath $S.paths.maaDir @('resource', 'item_index.json')
    if (Test-GdPathReady $path) {
        try {
            $j = Read-GdJson -Path $path
            foreach ($p in @($j.PSObject.Properties)) {
                $id = [string]$p.Name
                $nm = [string](Get-GdMapValue $p.Value 'name')
                if (-not $id -or -not $nm) { continue }
                if (-not $n2i.ContainsKey($nm)) { $n2i[$nm] = $id }
                $i2n[$id] = $nm
            }
        } catch { Write-GdLog "item_index.json 解析失败：$($_.Exception.Message)" -Level WARN }
    }
    $global:GdArkItemMaps = @{ NameToId = $n2i; IdToName = $i2n }
    return $global:GdArkItemMaps
}

function Parse-GdArkFarmTargetSpec {
    <# 转发壳(批次 5)：一行目标清单 → @{Key;Target;Stages;Bad}，三种写法与拒绝文案的规则在
       C#(parse-farm-target-spec)。Found:false = 旧语义的"整行作废返回 `$null`(Raw 缺失/空串)"。 #>
    param($Raw)
    $d = Invoke-GdCli -Verb 'parse-farm-target-spec' -Body ([pscustomobject]@{ raw = $Raw })
    if (-not $d.Found) { return $null }
    return $d.Spec
}

function Parse-GdArkDropText {
    <# 转发壳(批次 5)：gui.log 片段 → 掉落块数组 @{Stage;Items}，剥前缀/块头/配对正则/拒绝表的
       规则在 C#(parse-ark-drop-text)。空片段照旧回空数组。 #>
    param([string]$Text)
    return (Invoke-GdCli -Verb 'parse-ark-drop-text' -Body ([pscustomobject]@{ text = $Text })).Blocks
}

function Read-GdArkFarmLedger {
    <# 读两本账(inventory/droptable)。文件不在就是空账，不抛 —— 首跑 Resolve 先于任何记账。 #>
    param([Parameter(Mandatory)]$S)
    $inv = @{ byId = @{}; origin = @{}; offset = $null }
    $dt = @{}
    $p1 = Get-GdArkFarmInventoryPath
    if (Test-Path -LiteralPath $p1) {
        try {
            $j = Read-GdJson -Path $p1
            foreach ($p in @($j.byId.PSObject.Properties)) {
                $inv.byId[$p.Name] = [int](Get-GdMapValue $p.Value 'count')
                $inv.origin[$p.Name] = [string](Get-GdMapValue $p.Value 'origin')
            }
            if ($j.offset) { $inv.offset = @{ path = [string]$j.offset.path; offset = [long]$j.offset.offset } }
        } catch { Write-GdLog "ark-inventory.json 读不了($($_.Exception.Message))，按空账处理" -Level WARN }
    }
    $p2 = Get-GdArkFarmDropTablePath
    if (Test-Path -LiteralPath $p2) {
        try {
            $j = Read-GdJson -Path $p2
            foreach ($pi in @($j.PSObject.Properties)) {
                $one = @{}
                foreach ($ps in @($pi.Value.PSObject.Properties)) {
                    $one[$ps.Name] = @{ runs = [int](Get-GdMapValue $ps.Value 'runs'); qty = [int](Get-GdMapValue $ps.Value 'qty') }
                }
                $dt[$pi.Name] = $one
            }
        } catch { Write-GdLog "ark-droptable.json 读不了($($_.Exception.Message))，学习关系按空处理" -Level WARN }
    }
    return @{ Inventory = $inv; DropTable = $dt }
}

function Update-GdArkFarmLedger {
    <# 从 gui.log 的新增段记掉落账。偏移按 @{path;offset} 成对存(和监工同一纪律)：
       首拍/换路径(跨天轮转)只对末尾，绝不回扫旧日志 —— 上上轮就是拿首拍扫全文把 7 月的旧完成线记进了账。
       返回一句给人看的总结；什么都不新才回空串。 #>
    param([Parameter(Mandatory)]$S)
    $P = Get-MaaPaths -S $S
    if (-not (Test-GdPathReady $P.GuiLog)) { return '' }
    $maps = Get-GdArkItemMaps -S $S
    $led = Read-GdArkFarmLedger -S $S
    $inv = $led.Inventory; $dt = $led.DropTable

    # 首跑标定：账本文件还不存在 + MAA 有 DepotData 缓存 → 拿它当"估算初值"(origin=depot)，
    # 目的只有一个：别让目标清单里已经有的货被当成 0 从头狂刷。
    $initialized = ''
    if (-not (Test-Path -LiteralPath (Get-GdArkFarmInventoryPath))) {
        $depot = Join-GdPath $S.paths.maaDir @('data', 'DepotData.json')
        if (Test-GdPathReady $depot) {
            try {
                $d = Read-GdJson -Path $depot
                # 循环变量别写 $p：PowerShell 不分大小写，会踩掉本函数 108 行的 $P(Get-MaaPaths)，
                # 下面 Get-Item -LiteralPath $P.GuiLog 就绑到空串(与 lib\maa.ps1 266 行那族同一个坑)。
                foreach ($dp in @($d.data.PSObject.Properties)) {
                    $c = 0
                    if ([int]::TryParse([string]$dp.Value, [ref]$c) -and $c -gt 0) {
                        $inv.byId[$dp.Name] = $c
                        $inv.origin[$dp.Name] = 'depot'
                    }
                }
                $initialized = "已按 MAA 库存缓存标定初值($($inv.byId.Count) 项，估算)"
            } catch { $initialized = 'DepotData 读不动，初值按 0 起账' }
        } else { $initialized = '没有库存缓存，初值按 0 起账(会先多刷一轮才收敛)' }
    }

    $item = Get-Item -LiteralPath $P.GuiLog
    $off = 0
    if ($inv.offset -and [string]$inv.offset.path -eq $P.GuiLog -and $item.Length -ge $inv.offset.offset) {
        $off = [long]$inv.offset.offset
    }
    $tail = Get-GdFileTail -Path $P.GuiLog -Offset $off
    $blocks = @(Parse-GdArkDropText -Text $tail.Text)

    $touched = @{}; $unk = @{}; $plus = 0
    foreach ($b in $blocks) {
        foreach ($it in $b.Items) {
            $id = [string]$maps.NameToId[$it.Name]
            if (-not $id) { $unk[$it.Name] = $true; continue }
            $have = 0
            if ($inv.byId.ContainsKey($id)) { $have = [int]$inv.byId[$id] }
            if ($it.Delta -gt 0) {
                $inv.byId[$id] = $have + $it.Delta
                $inv.origin[$id] = 'drops'
                $plus += $it.Delta
            }
            $touched[$id] = $true
            if ($b.Stage) {
                if (-not $dt.ContainsKey($id)) { $dt[$id] = @{} }
                $one = $dt[$id]
                $runs = 0; $qty = 0
                if ($one.ContainsKey($b.Stage)) { $runs = [int]$one[$b.Stage].runs; $qty = [int]$one[$b.Stage].qty }
                $one[$b.Stage] = @{ runs = ($runs + 1); qty = ($qty + [int]$it.Delta) }
            }
        }
    }
    if (-not $blocks.Count -and -not $initialized) { return '' }

    $offsetObj = [pscustomobject]@{ path = $P.GuiLog; offset = [long]$tail.Offset }
    $byIdObj = [ordered]@{}
    foreach ($k in @($inv.byId.Keys | Sort-Object)) {
        $byIdObj[$k] = [pscustomobject]@{ count = [int]$inv.byId[$k]; origin = [string]$inv.origin[$k]; updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    }
    $dtObj = [ordered]@{}
    foreach ($k in @($dt.Keys | Sort-Object)) {
        $one = [ordered]@{}
        foreach ($st in @($dt[$k].Keys | Sort-Object)) { $one[$st] = [pscustomobject]@{ runs = [int]$dt[$k][$st].runs; qty = [int]$dt[$k][$st].qty } }
        $dtObj[$k] = [pscustomobject]$one
    }
    Write-GdJson -Path (Get-GdArkFarmInventoryPath) -Object ([pscustomobject]@{ version = 1; offset = $offsetObj; byId = [pscustomobject]$byIdObj })
    Write-GdJson -Path (Get-GdArkFarmDropTablePath) -Object ([pscustomobject]$dtObj)
    # 没在 item_index 里认出来的名字记一笔(留 30 条)——材料改名/表没更到时，这里是第一现场
    if ($unk.Count) {
        $known = @()
        if (Test-Path -LiteralPath (Get-GdArkFarmDropsPath)) { try { $known = @(Read-GdJson -Path (Get-GdArkFarmDropsPath)) } catch { $known = @() } }
        foreach ($nm in @($unk.Keys)) { if ($known -notcontains $nm) { $known += $nm } }
        if ($known.Count -gt 30) { $known = @($known | Select-Object -Last 30) }
        Write-GdJson -Path (Get-GdArkFarmDropsPath) -Object @($known)
    }
    $bits = @()
    if ($initialized) { $bits += $initialized }
    if ($blocks.Count) { $bits += "记了 $($blocks.Count) 场掉落、入账 +$plus" }
    if ($unk.Count) { $bits += "$($unk.Count) 个名字没在材料表认出来($((@($unk.Keys) | Select-Object -First 3) -join '/'))" }
    return ($bits -join '；')
}

function Resolve-ArkFarmPlan {
    <# 转发壳(批次 5)：判表(一次只锁缺口最大、挑关排序、次数折算与封顶、全部文案)的规则在
       C#(resolve-ark-farm-plan)。这里保持**旧签名不变**(test-ark 直接按命名参数喂假数据)，
       只把八样值装进信封；返回信封 data(PSCustomObject，属性名与顺序和旧版逐字一致)。 #>
    param(
        # 不写 Mandatory：最常见的第一跑就是"清单还没配"的空数组，Mandatory 会把空集合直接拒在参数绑定上
        [array]$Targets,
        $NameToId = @{}, $IdToName = @{},
        $Inventory = @{}, $Origin = @{},
        $DropTable = @{}, $KnownStages = @{},
        [int]$MaxTimes = 12
    )
    return Invoke-GdCli -Verb 'resolve-ark-farm-plan' -Body ([pscustomobject]@{
        targets = $Targets
        nameToId = $NameToId
        idToName = $IdToName
        inventory = $Inventory
        origin = $Origin
        dropTable = $DropTable
        knownStages = $KnownStages
        maxTimes = $MaxTimes
    })
}

function Get-GdArkFarmTargetsNormalized {
    <# settings.ark.farmTargets → 规整过的目标数组(带 Bad 的也留着，让判定层去说) #>
    param([Parameter(Mandatory)]$S)
    $out = @()
    foreach ($raw in @(Get-GdMapValue $S.ark 'farmTargets')) {
        $t = Parse-GdArkFarmTargetSpec -Raw $raw
        if ($t) { $out += $t }
    }
    return $out
}

function Sync-GdArkFarmHaveFromDepot {
    <# 判缺口之前把 farmTargets 里材料的"现有量"用 MAA 仓库缓存(data\DepotData.json)实时刷一遍(2026-09-26)。
       规矩只有一条：缓存文件比自家账本新才采信 —— 账本吃的是全量 (+N) 增量，缓存比它旧时
       采信会把增量清零、反向多刷。缓存里没有该材料 = 同步那次是 0。
       只改内存里的 $Led 并回一句说明，不写盘(写盘留给收尾的 Update-GdArkFarmLedger)。 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Targets, [Parameter(Mandatory)]$NameToId, [Parameter(Mandatory)]$Led)
    $wantIds = @()
    foreach ($t in @($Targets)) {
        if ([string]$t.Bad) { continue }
        $id = ''
        if ($t.Key -match '^\d{3,8}$') { $id = $t.Key }
        elseif ($NameToId.ContainsKey($t.Key)) { $id = [string]$NameToId[$t.Key] }
        if ($id -and ($wantIds -notcontains $id)) { $wantIds += $id }
    }
    if (-not $wantIds.Count) { return '' }
    $depot = Join-GdPath $S.paths.maaDir @('data', 'DepotData.json')
    if (-not (Test-GdPathReady $depot)) { return '' }
    $invPath = Get-GdArkFarmInventoryPath
    if ((Test-Path -LiteralPath $invPath) -and
        (Get-Item -LiteralPath $depot).LastWriteTime -le (Get-Item -LiteralPath $invPath).LastWriteTime) { return '' }
    $d = $null
    try { $d = Read-GdJson -Path $depot } catch { return '' }
    if (-not $d -or -not $d.data) { return '' }
    $bits = @()
    foreach ($id in $wantIds) {
        $c = 0
        $v = Get-GdMapValue $d.data $id
        if ($v) { [void][int]::TryParse([string]$v, [ref]$c) }
        $old = -1
        if ($Led.Inventory.byId.ContainsKey($id)) { $old = [int]$Led.Inventory.byId[$id] }
        if ($old -ne $c) {
            $Led.Inventory.byId[$id] = $c
            $Led.Inventory.origin[$id] = 'depot'
            $bits += "id=$id 现值 $old→$c"
        }
    }
    if (-not $bits.Count) { return '' }
    return "库存缓存比账本新，已按实时读数纠偏：" + ($bits -join '；')
}

function Resolve-GdArkFarmDecision {
    <# 活层：把 settings/账本/MAA 两张表都读出来喂给纯判定。返回方案或 $null(功能关了)。
       -Dedicated(=-FarmArk 专用轮)时活动确认门不适用：材料本不吃活动代币；
       需求优先档(farmAppend)只在长草(idle)方案上生效 —— 活动期理智金贵，不去挤活动代币的位。 #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision, [switch]$Dedicated)

    if (-not $Dedicated -and $S.ark.farmAppend -eq $false) { return $null }
    if (-not $Dedicated -and [string]$Decision.Mode -ne 'idle') { return $null }
    <# 今日已认栽(MAA 判关卡计划内没有当日开放的关卡，剔关重试也全关) → 顺带档不再前置补刷关，
       当天后续轮直接按长草计划走，不陪 MAA 空试。-FarmArk 专用轮是人的明确指令，不吃这条防线。 #>
    if (-not $Dedicated -and (Test-GdArkFightSkipMarkToday -S $S)) {
        Write-GdLog '补刷前置今日已认栽(MAA 判关卡全关) → 本轮不前置补刷关，按长草计划走'
        return $null
    }

    $maps = Get-GdArkItemMaps -S $S
    $led = Read-GdArkFarmLedger -S $S
    $targetsNorm = @(Get-GdArkFarmTargetsNormalized -S $S)
    $syncNote = Sync-GdArkFarmHaveFromDepot -S $S -Targets $targetsNorm -NameToId $maps.NameToId -Led $led
    if ($syncNote) { Write-GdLog "补刷纠偏：$syncNote" }
    $known = @{}
    foreach ($k in @(Get-GdStageTable -S $S).Keys) { $known[$k] = $true }
    $mt = 12; [void][int]::TryParse([string]$S.ark.farmMaxTimesPerRound, [ref]$mt)

    $fp = Resolve-ArkFarmPlan -Targets $targetsNorm `
        -NameToId $maps.NameToId -IdToName $maps.IdToName `
        -Inventory $led.Inventory.byId -Origin $led.Inventory.origin `
        -DropTable $led.DropTable -KnownStages $known -MaxTimes $mt
    if (-not $fp.Active) {
        if ($Dedicated) { Write-GdLog "专用材料轮没有可刷的目标：$($fp.Reason)" -Level WARN }
        return $null
    }
    if (-not $Dedicated) {
        # 顺带档：Times 在这里没有执行语义(不碰 MAA 的任何开关，止损靠理智本身)，
        # 判定照算、由接线层只取 Stages 拼进计划 —— 留着是为了让预览能说"约需 N 场"。
        return $fp
    }
    return $fp
}

function Format-GdArkFarmLine {
    <# 给 status/预览用的一行字；方案为空给"为什么没刷" #>
    param($Plan)
    if (-not $Plan) { return '材料补刷：本轮不追加(ark.farmTargets 没配、功能关了、或今天不是长草方案)' }
    return "材料补刷：$($Plan.Reason)"
}
