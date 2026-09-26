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

function Get-GdArkFarmInventoryPath { Join-Path $global:GD.State 'ark-inventory.json' }
function Get-GdArkFarmDropTablePath { Join-Path $global:GD.State 'ark-droptable.json' }
function Get-GdArkFarmDropsPath    { Join-Path $global:GD.State 'ark-farm-drops.json' }

function Get-GdArkItemMaps {
    <# MAA 自带 resource/item_index.json → 材料名↔代号两张表(进程内缓存)。
       475 条覆盖常规材料，但装备模组那类新货币不在表里 —— 认不出来的材料由调用方明说，不猜。 #>
    param([Parameter(Mandatory)]$S)
    # 懒初始化：common.ps1 开着 StrictMode 1.0，直接读未声明的 $global:GdArkItemMaps 会当场报错(和 Get-GdEntryVerbs 同一招)
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
    <# 一行目标清单 → @{Key;Target;Stages;Bad}。吃三种写法：
         "D32钢=30"、"D32钢=30@CE-5"、"30135=30@CE-5,CE-4"(键是材料名或 MAA 材料代号)；
       也吃 json 对象 { item/target/stages }。解析不动的返回 Bad 说明，调用方汇总着说，不静默丢。 #>
    param($Raw)
    if ($null -eq $Raw) { return $null }
    if ($Raw -is [string]) {
        $t = $Raw.Trim()
        if (-not $t) { return $null }
        if ($t -match '^(?<k>.+?)\s*[=＝]\s*(?<n>\d+)(?:\s*@\s*(?<s>.+))?$') {
            $stages = @()
            if ($Matches.s) { $stages = @($Matches.s -split '[,，、;；\s]+' | Where-Object { $_ }) }
            return @{ Key = $Matches.k.Trim(); Target = [int]$Matches.n; Stages = $stages; Raw = $t; Bad = '' }
        }
        return @{ Key = ''; Target = 0; Stages = @(); Raw = $t; Bad = "看不懂「$t」，要写成 材料名=数量[@关卡1,关卡2]" }
    }
    $k = [string](Get-GdMapValue $Raw 'item'); if (-not $k) { $k = [string](Get-GdMapValue $Raw 'name') }
    $n = 0; [void][int]::TryParse([string](Get-GdMapValue $Raw 'target'), [ref]$n)
    if (-not $n) { [void][int]::TryParse([string](Get-GdMapValue $Raw 'count'), [ref]$n) }
    $s = @(Get-GdMapValue $Raw 'stages')
    if ($s.Count -eq 1 -and $s[0] -is [string]) { $s = @(($s[0] -split '[,，、;；\s]+' | Where-Object { $_ })) }
    if (-not $k) { return @{ Key = ''; Target = 0; Stages = @(); Raw = ($Raw | ConvertTo-Json -Compress); Bad = '条目里没有材料名/代号(item)' } }
    if ($n -le 0) { return @{ Key = $k; Target = 0; Stages = $s; Raw = "$k"; Bad = "$k 的目标数量没写或不是正整数" } }
    return @{ Key = $k; Target = $n; Stages = @($s); Raw = "$k=$n"; Bad = '' }
}

function Parse-GdArkDropText {
    <# 纯函数：gui.log 片段 → 掉落块数组 @{Stage; Items=@(@{Name;Delta})}。
       实测形状(2026-09-26 从真 gui.log 抄的，这里全是编的数据)：
         [08:50:26] PR-B-2 掉落统计:
         术师芯片组 : 2 (+2)   狙击芯片组 : 1 (+1)   当前次数 : 3
       只认 (+N) 的增量记账；"当前次数/理智/用时"这类同名不同物的行靠拒绝表挡掉。
       块头只按「<代号> 掉落统计」抓关卡代号，抓不到就把 Stage 记空(掉还是记，只丢学习关系)。 #>
    param([string]$Text)
    $blocks = @()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $blocks }
    $cur = $null
    foreach ($line in ($Text -split "`r?`n")) {
        $s = $line.Trim()
        if (-not $s) { continue }
        $s = ($s -replace '^\[[^\]]*\]\s*', '') -replace '^<\d+>\s*', ''
        if ($s -match '([A-Za-z0-9][A-Za-z0-9\-]*)\s*掉落统计') {
            # 块必须是 [pscustomobject]：hashtable += 进数组会被摊开成一个个字典项(老坑，见记忆)
            $cur = [pscustomobject]@{ Stage = $Matches[1]; Items = @() }
            $blocks += $cur
            continue
        }
        if (-not $cur) { continue }
        $pairs = @([regex]::Matches($s, '([^\s:：,，、;()（）+]+)\s*[::]\s*(\d+)(?:\s*[（(]\s*\+(\d+)\s*[）)])?'))
        if ($pairs.Count -eq 0) { $cur = $null; continue }   # 掉落块是连续的，出现不像配额的行就算块结束了
        foreach ($m in $pairs) {
            $nm = $m.Groups[1].Value
            if ($nm -in @('当前次数', '理智', '剩余理智', '用时', '预计', '累计理智')) { continue }
            $delta = 0
            if ($m.Groups[3].Success) { $delta = [int]$m.Groups[3].Value }
            $cur.Items = @($cur.Items) + [pscustomobject]@{ Name = $nm; Delta = $delta }
        }
    }
    return $blocks
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
                foreach ($p in @($d.data.PSObject.Properties)) {
                    $c = 0
                    if ([int]::TryParse([string]$p.Value, [ref]$c) -and $c -gt 0) {
                        $inv.byId[$p.Name] = $c
                        $inv.origin[$p.Name] = 'depot'
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
    <# 纯判定(不联网、不写盘)：目标清单 + 账本 + 学习表 → 本轮补刷方案。
       一次只锁一个目标(MAA 一条 Fight 链只有一个指定材料位)，选"还差最多"的那个；
       刷哪关：显式填的 > 从掉落学习表里挑(每关平均掉最多、其次见得多的) > 不刷并说为什么。
       次数 = ceil(缺口 / 每场平均掉落)，封顶 MaxTimes —— 它只是 TimesLimit 的护栏，
       真正的止损是"专用轮里理智本身就有限"。 #>
    param(
        # 不写 Mandatory：最常见的第一跑就是"清单还没配"的空数组，Mandatory 会把空集合直接拒在参数绑定上
        [array]$Targets,
        $NameToId = @{}, $IdToName = @{},
        $Inventory = @{}, $Origin = @{},
        $DropTable = @{}, $KnownStages = @{},
        [int]$MaxTimes = 12
    )
    $none = {
        param($Why) [pscustomobject]@{ Active = $false; Reason = $Why; ItemId = ''; ItemName = ''; Have = 0; Target = 0; Gap = 0; Stages = @(); Times = 0 }
    }
    if ($MaxTimes -lt 1) { $MaxTimes = 1 }
    if (-not $Targets -or @($Targets).Count -eq 0) { return (& $none '没配 ark.farmTargets → 材料补刷未启动') }

    $notes = @(); $best = $null
    foreach ($t in $Targets) {
        if ([string]$t.Bad) { $notes += "跳过「$($t.Raw)」：$($t.Bad)"; continue }
        $id = ''; $nm = [string]$t.Key
        if ($t.Key -match '^\d{3,8}$') {
            $id = $t.Key
            if ($IdToName.ContainsKey($id)) { $nm = [string]$IdToName[$id] }
        } elseif ($NameToId.ContainsKey($t.Key)) { $id = [string]$NameToId[$t.Key] }
        if (-not $id) { $notes += "跳过「$($t.Raw)」：材料名在 MAA 材料表(item_index)里找不到"; continue }

        # 非泛型 Hashtable 没有 TryGetValue(5.1/7 都一样)，只能 ContainsKey 两步走
        $have = 0
        if ($Inventory.ContainsKey($id)) { $have = [int]$Inventory[$id] }
        $gap = [int]$t.Target - $have
        if ($gap -le 0) { $notes += "$nm 已够($have/$($t.Target))"; continue }

        $stages = @($t.Stages)
        if (-not $stages.Count) {
            # 没填关卡 → 从学习表挑：平均每场掉得最多的优先，并列取见得多的；最多挑 2 关
            # 契约：判定层所有映射参数都是 hashtable(IO 层产出的就是 hashtable，非 JSON 对象)
            $learned = @()
            if ($DropTable.ContainsKey($id)) {
                foreach ($st in @($DropTable[$id].Keys)) {
                    $v = $DropTable[$id][$st]
                    $runs = [int](Get-GdMapValue $v 'runs'); $qty = [int](Get-GdMapValue $v 'qty')
                    if ($runs -gt 0 -and $qty -gt 0) { $learned += [pscustomobject]@{ Stage = $st; Avg = ($qty / $runs); Runs = $runs } }
                }
            }
            $stages = @($learned | Sort-Object @{ Expression = 'Avg'; Descending = $true }, @{ Expression = 'Runs'; Descending = $true } | Select-Object -First 2 -ExpandProperty Stage)
            if (-not $stages.Count) { $notes += "$nm 还差 $gap，但不知道该刷哪关(清单里没填、掉落账本也没教过) → 把它写成 $($t.Raw)@CE-5 这种带关卡的形式"; continue }
        }
        $badSt = @()
        if ($KnownStages.Count) { $badSt = @($stages | Where-Object { -not $KnownStages.ContainsKey($_) }) }
        $stOk = @($stages | Where-Object { $badSt -notcontains $_ })
        if (-not $stOk.Count) { $notes += "$nm 还差 $gap，但关卡 $($badSt -join '/') 不被 MAA 关卡表认识 → 先更 MAA 资源或改 farmTargets"; continue }

        # 每场平均掉落：只按真正会刷到的关算；没学习数据就按 1 估并明说
        $tq = 0; $tr = 0
        if ($DropTable.ContainsKey($id)) {
            foreach ($st in $stOk) {
                $v = Get-GdMapValue $DropTable[$id] $st
                if ($v) { $tq += [int](Get-GdMapValue $v 'qty'); $tr += [int](Get-GdMapValue $v 'runs') }
            }
        }
        $avg = 1.0; $avgNote = '掉落率未知，按每场 1 估'
        if ($tr -gt 0) { $avg = [Math]::Max($tq / $tr, 0.1); $avgNote = "按学习到的每场约 $([Math]::Round($avg, 1))" }
        $times = [int][Math]::Ceiling($gap / $avg)
        $capNote = ''
        if ($times -gt $MaxTimes) { $times = $MaxTimes; $capNote = "(单轮封顶 $MaxTimes，剩下的明天接着刷)" }

        $cand = [pscustomobject]@{ Active = $true; ItemId = $id; ItemName = $nm; Have = $have; Target = [int]$t.Target; Gap = $gap; Stages = $stOk; Times = $times; Avg = $avg; AvgNote = $avgNote; CapNote = $capNote; BadStages = $badSt }
        if (-not $best -or $gap -gt $best.Gap) { $best = $cand }
    }
    if (-not $best) {
        $why = '本轮没有要补刷的材料'
        if ($notes.Count) { $why = "本轮没有要补刷的材料：$($notes -join '；')" }
        return (& $none $why)
    }
    $originNote = ''
    if ([string]$Origin[$best.ItemId] -eq 'depot') { $originNote = '(现值来自库存缓存标定，是估算)' }
    $badNote = ''
    if (@($best.BadStages).Count) { $badNote = "；已剔除不认识的关卡 $($best.BadStages -join '/')" }
    [pscustomobject]@{
        Active = $true
        ItemId = $best.ItemId; ItemName = $best.ItemName
        Have = $best.Have; Target = $best.Target; Gap = $best.Gap
        Stages = $best.Stages; Times = $best.Times
        Reason = "补刷 $($best.ItemName)×$($best.Times) @$($best.Stages -join ',')：目标 $($best.Target)，现有 $($best.Have)$originNote，还差 $($best.Gap)，$($best.AvgNote)$($best.CapNote)$badNote"
        Notes = $notes
    }
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
