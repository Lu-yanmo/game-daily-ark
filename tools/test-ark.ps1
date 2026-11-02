# tools/test-ark.ps1 — 明日方舟那一路的纯逻辑自检(只读：不改配置、不启动任何程序)
# 用法: pwsh -NoProfile -File tools\test-ark.ps1
# 1999 那一路在 tools\test-r1999.ps1；两边都跑用 tools\test-decisions.ps1。
# 公共那半套(计数器、临时 state 的存与取、[t1]/[t11])在 tools\test-lib.ps1。
param([switch]$NoExit)

. (Join-Path $PSScriptRoot 'test-lib.ps1')
Show-GdCommonTimeChecks
Show-GdCommonPathChecks
Show-GdCommonVerbChecks
Show-GdCommonEntryHintChecks
Show-GdCommonScriptHygieneChecks
Show-GdCommonEmptyPathChecks
Show-GdCommonRunLockChecks
Show-GdCommonScreensaverChecks

# ---- B-3②-d 刀①(11-01)静态锚：三枚 state 读件的"两臂都在"，钉在 maaDir 那道现场门之前 ----
# 为什么放这里：这一格钉的是源码形状，MAA 目录在不在都该有证词(只读自检不许要求机器现场状态)；
# 放在下面那道 return 之后，没配 paths.maaDir 的机器上它就静默不跑，等于把锚做成哑尺。
# 剥注释照 tools\test-r1999.ps1 那两形(-replace 逐字复用)：本批这三枚读件的**函数体内就写了**
# `read-decision-state`、`Get-GdStateObject` 这些词(那是语义边界登记，不是调用)，不剥注释的正向锚
# 会在真身被摘掉后照样绿——那是本仓登记过的"锚不是调用"形。
# 用 .Contains() 而不是 -match：这里钉的是**逐字符号**(整块字面量里带 $ 与引号)，正则反而要为转义多写一层。
$fnAck = [string](Get-Command Get-GdAckMap -ErrorAction SilentlyContinue).Definition
$fnAck = ($fnAck -replace '(?s)<\#.*?\#>', ' ') -replace '(?m)^\s*#.*$', ' '
$fnShop = [string](Get-Command Get-GdShopDoneMap -ErrorAction SilentlyContinue).Definition
$fnShop = ($fnShop -replace '(?s)<\#.*?\#>', ' ') -replace '(?m)^\s*#.*$', ' '
$fnProbe = [string](Get-Command Get-GdArkEventProbe -ErrorAction SilentlyContinue).Definition
$fnProbe = ($fnProbe -replace '(?s)<\#.*?\#>', ' ') -replace '(?m)^\s*#.*$', ' '

Check '②-d 刀①核臂在(ack 表)：Get-GdAckMap 现问 read-decision-state，且 want 里只点 ack 那一枚' (
    $fnAck.Contains("Invoke-GdCli -Verb 'read-decision-state'") -and $fnAck.Contains("@{ game = `$Game; want = @('ack') }")) $(
    if ($fnAck.Length -eq 0) { 'Get-GdAckMap 不在场(尺没接到电)' } else { "len=$($fnAck.Length)" })
Check '②-d 刀①回落臂在(ack 表)：核不可用时仍由壳自己读 "$Game-event-ack" 的 acked 键(逐字＝改指前原样)' (
    $fnAck.Contains('Get-GdStateObject -Name "$Game-event-ack" -Default $null') -and $fnAck.Contains("Get-GdMapValue `$obj 'acked'"))

Check '②-d 刀①核臂在(领空表)：Get-GdShopDoneMap 现问同一把出口，且 want 里只点 shopDone 那一枚' (
    $fnShop.Contains("Invoke-GdCli -Verb 'read-decision-state'") -and $fnShop.Contains("@{ game = `$Game; want = @('shopDone') }")) $(
    if ($fnShop.Length -eq 0) { 'Get-GdShopDoneMap 不在场(尺没接到电)' } else { "len=$($fnShop.Length)" })
Check '②-d 刀①回落臂在(领空表)：核不可用时仍由壳自己读 "$Game-shop-done" 的 done 键(逐字＝改指前原样)' (
    $fnShop.Contains('Get-GdStateObject -Name "$Game-shop-done" -Default $null') -and $fnShop.Contains("Get-GdMapValue `$obj 'done'"))

Check '②-d 刀①核臂在(自证账)：Get-GdArkEventProbe 现问 read-decision-state，game 恒点名 ark(那枚文件名是常量)' (
    $fnProbe.Contains("Invoke-GdCli -Verb 'read-decision-state'") -and $fnProbe.Contains("@{ game = 'ark'; want = @('probe') }")) $(
    if ($fnProbe.Length -eq 0) { 'Get-GdArkEventProbe 不在场(尺没接到电)' } else { "len=$($fnProbe.Length)" })
Check '②-d 刀①判形在(自证账)：问的是属性在不在，不是值在不在(null 在这里是合法读数＝这一轮没探过；把它当核没答就把自证读成空表)' (
    $fnProbe.Contains("`$null -ne `$core.PSObject.Properties['Probe']") -and $fnProbe.Contains("if (`$null -eq `$core.Probe) { return `$null }"))
Check '②-d 刀①回落臂在(自证账)：核不可用时仍由壳自己走 路径→Test-Path→读 json→EventKey 判空(逐字＝改指前原样)' (
    $fnProbe.Contains('Get-GdArkEventProbePath') -and $fnProbe.Contains('-not [string]$m.EventKey'))

# 语义边界那一格(三枚读件共同的那句话)：这两枚表读件**不取**核顺手摆上桌的 ShopDoneGateOpen——
# 领空门的"给不给"仍归 Test-GdShopDoneEnabled(表账「不许动」那一档)，这里若哪天改成读那枚读数，就是第二条尺进场，得先拍。
Check '②-d 刀①语义边界：ack／领空两枚表读件都不消费 ShopDoneGateOpen(那把 flag 尺仍只有 Test-GdShopDoneEnabled 一枚)' (
    -not $fnAck.Contains('ShopDoneGateOpen') -and -not $fnShop.Contains('ShopDoneGateOpen')) $(
    'ackLen=' + $fnAck.Length + ' shopLen=' + $fnShop.Length)

# [t2] 往后的每一组都要读 MAA 自己的文件(关卡表 resource\stages.json、队列 configuration.json)。
# paths.maaDir 还没填(exe 第一次跑、只 setup -SkipScan 过)就先说人话：
# 放下去只会变成 "无法将自变量绑定到参数 'Path'，因为它是空字符串" 那种看不懂的报错(2026-09-24 首跑就是这样)。
if (-not (Test-GdPathReady $S.paths.maaDir)) {
    Write-Host "`n  MAA 目录还没填或不存在 → [t2] 之后的断言跑不了，先跑 setup.ps1 探测安装位置" -ForegroundColor Yellow
    Check '助手目录已填好，这套自检才有意义(先跑 setup.ps1)' $false "paths.maaDir=[$($S.paths.maaDir)]"
    $res = Show-GdTestResult -Tag 'ark'
    if ($NoExit) { return $res }
    exit 1
}

Write-Host "`n[t2] 关卡表 / 校验"
$table = Get-GdStageTable -S $S
Check '关卡表非空' ($table.Count -gt 300) "$($table.Count) 条"
$chk = Test-GdStages -S $S -StageText 'CE-5, LS-5'
Check '多关卡拆分+去空格' ($chk.Stages.Count -eq 2 -and $chk.Bad.Count -eq 0) $chk.Note
Check '理智合计' ($chk.Cost -eq ([int]$table['CE-5'] + [int]$table['LS-5'])) "$($chk.Cost)"
Check '未知关卡能抓出' ((Test-GdStages -S $S -StageText 'XX-9').Bad.Count -eq 1)

Write-Host "`n[t3] MAA 队列改写(仅预览，不落盘)"
$cfgPath = Join-GdPath $S.paths.maaDir @($S.paths.maaConfig)
$hashBefore = (Get-FileHash -LiteralPath $cfgPath -Algorithm SHA256).Hash
$base = @{ Source = 'test'; EventKey = $null; EventTip = $null; StageHint = $null }
function FightFlags($preview) {
    $out = @{}
    foreach ($q in @((Read-GdJson -Path $cfgPath).Configurations.Default.TaskQueue)) {
        if ($q.TaskType -eq 'Fight') { $out[[string]$q.Name] = [bool]$q.IsEnable }
    }
    return $out
}

$r1 = Set-MaaDailyConfig -S $S -Decision ($base + @{ Mode = 'idle'; Stage = 'CE-5,LS-5'; ClearSanity = $true })
$disk = FightFlags $null
$wantsOn = (@($r1.Changes | Where-Object { $_ -match '剩余理智 → IsEnable=True' }).Count -gt 0)
Check 'idle: 剩余理智最终会被启用' ([bool]$disk[[string]$S.ark.finishAllSanityWith] -or $wantsOn) "现状=$([bool]$disk[[string]$S.ark.finishAllSanityWith]) 本次改写=$wantsOn"
Check 'idle: 期望链路含 Fight' ('Fight' -in $r1.ExpectedChains) ($r1.ExpectedChains -join ',')
Check 'idle: 理智计划写入' (@($r1.Changes | Where-Object { $_ -match 'StagePlan = CE-5,LS-5' }).Count -gt 0 -or $disk.Count -gt 0) ($r1.Changes -join ' | ')
$keepOk = $true
foreach ($k in @($S.ark.keepQueuesEnabled)) { if ("$k" -notin $r1.ExpectedChains) { $keepOk = $false } }
Check 'idle: 日常链路都在启用集' $keepOk ($r1.ExpectedChains -join ',')
Check 'idle: 肉鸽/生息演算不在启用集' (@($S.ark.disableQueues | Where-Object { $_ -in $r1.ExpectedChains }).Count -eq 0)
Check '预览不落盘' ((Get-FileHash -LiteralPath $cfgPath -Algorithm SHA256).Hash -eq $hashBefore)

$r2 = Set-MaaDailyConfig -S $S -Decision ($base + @{ Mode = 'event-pending'; Stage = 'SR-8'; ClearSanity = $false })
Check '不烧理智的形状: 不写 Fight' ('Fight' -notin $r2.ExpectedChains) ($r2.ExpectedChains -join ',')

$r3 = Set-MaaDailyConfig -S $S -Decision ($base + @{ Mode = 'event'; Stage = 'SR-8'; ClearSanity = $true })
Check 'event 档: 刷活动关' ('Fight' -in $r3.ExpectedChains -and (@($r3.Changes | Where-Object { $_ -match 'StagePlan = SR-8' }).Count -gt 0))
$r4 = $null
try { Set-MaaDailyConfig -S $S -Decision ($base + @{ Mode = 'idle'; Stage = 'NOT-A-STAGE'; ClearSanity = $true }) | Out-Null } catch { $r4 = $_.Exception.Message }
Check '坏关卡代号会被拦住' ($r4 -and $r4 -match 'NOT-A-STAGE')

Write-Host "`n[t5] 方舟判定链路(会联网拉一次活动接口)"
$a = Get-ArkEvent -S $S
Check '返回模式合法' (@('idle', 'event', 'event-pending') -contains $a.Mode) "mode=$($a.Mode) stage=$($a.Stage)"
Check '有理智计划' ($a.Stage -and (Test-GdStages -S $S -StageText ([string]$a.Stage)).Bad.Count -eq 0) (Test-GdStages -S $S -StageText ([string]$a.Stage)).Note
# 这条判据在 2026-10-12 第 1 刀**反了向**：旧口径是"没确认就整轮不烧理智"，
# 新口径是"今天自证进不去 → 当日改刷长草套餐，理智照烧"(用户原话「活动要打…没打通就别空烧」)。
Check 'event-pending 当日仍烧理智(改刷长草，不空放)' (-not ($a.Mode -eq 'event-pending' -and -not $a.ClearSanity)) "mode=$($a.Mode) clear=$($a.ClearSanity)"
$b = Get-ArkEvent -S $S -Offline
Check '离线可降级' (@('idle', 'event', 'event-pending') -contains $b.Mode) "source=$($b.Source)"

Write-Host "`n[t7] 活动门(每轮自证)+商店领空 gate(假数据 + 临时 state，跑完还原)"
# ark-event-ack 那本账不再参与方舟判定(10-12 第 1 刀)，这里就不快照它了；快照 ark-event-probe 是因为探针档会写盘。
Save-GdTestState -Names @('ark-event-probe', 'ark-shop-done')
function Set-FakeArkProbe {
    <# 第 1 刀(2026-10-12)的夹具：往 state\ark-event-probe.json 写一条"活动图自证结论"。
       正常路径上这文件只由 lib\ark-module.ps1 的 Run 钩子(Update-GdArkEventProbe)写；自检不许起进程、
       也不许读真日志(那会要求机器现场状态)，所以这里直接落夹具，跑完由 Restore-GdTestState 还原。 #>
    param([string]$Date, [string]$Key = 'zztest-event', [string]$Stage = 'AI-8', [bool]$Entered = $true,
          [string]$Evidence = '假数据：MAA 的关卡名单里选中了 AI-8')
    Write-GdJson -Path (Get-GdArkEventProbePath) -Object ([ordered]@{
        Date = $Date; EventKey = $Key; Stage = $Stage; Entered = $Entered; Evidence = $Evidence
    })
}
function Clear-FakeArkProbe { Remove-Item -LiteralPath (Get-GdArkEventProbePath) -Force -ErrorAction SilentlyContinue }
function New-FakeArkData {
    param([array]$Events)
    $grp = New-Object psobject
    foreach ($e in $Events) {
        $stages = @($e.Stages | ForEach-Object { New-Object psobject -Property @{ Value = $_; Drop = '10000' } })
        $act = New-Object psobject -Property @{ Tip = $e.Tip; UtcStartTime = $e.Start; UtcExpireTime = $e.End }
        $grp | Add-Member -NotePropertyName $e.Id -NotePropertyValue (New-Object psobject -Property @{ Activity = $act; Stages = $stages }) -Force
    }
    return New-Object psobject -Property @{ Official = (New-Object psobject -Property @{ sideStoryStage = $grp }) }
}
$nowMs = Get-GdNowMs
$dayAgo = (Get-Date).AddDays(-1).ToString('yyyy/MM/dd HH:mm:ss')
$dayAfter = (Get-Date).AddDays(6).ToString('yyyy-MM-dd HH:mm:ss')
$fake = New-FakeArkData @(@{ Id = 'zztest-event'; Tip = '测试活动'; Start = $dayAgo; End = $dayAfter; Stages = @('AI-8', 'CE-5') })
$two = New-FakeArkData @(@{ Id = 'zztest-event'; Tip = '测试活动A'; Start = $dayAgo; End = $dayAfter; Stages = @('AI-8') },
    @{ Id = 'zztest-event2'; Tip = '测试活动B'; Start = $dayAgo; End = (Get-Date).AddDays(9).ToString('yyyy-MM-dd HH:mm:ss'); Stages = @('LS-5') })
try {
    $idleStage = [string]$S.ark.defaultStage
    $today = (Get-Date).ToString('yyyy-MM-dd')
    # 第 1 刀(2026-10-12)：这一段的判据从"有没有敲 -AckArk"换成"state\ark-event-probe.json 那条自证结论"。
    # 原来那格"入口覆盖参数名后提示语跟着改"整条退场 —— ark 的提示语不再引用任何 Ack 参数名。
    Clear-FakeArkProbe
    $p1 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '没有自证结论 → 本轮即以活动最后一关当探针(理智照烧)' ($p1.Mode -eq 'event' -and $p1.Stage -eq 'AI-8' -and $p1.ClearSanity) "mode=$($p1.Mode) stage=$($p1.Stage)"
    Check '探针档把活动关卡留在 StageHint(收尾采集照它点名)' ($p1.StageHint -eq 'AI-8') $p1.StageHint
    Check '探针档的提示语讲清"为探针"，且不再出现任何 Ack 参数名' (($p1.Reason -match '为探针') -and ($p1.Reason -notmatch 'Ack')) $p1.Reason
    Set-FakeArkProbe -Date $today -Entered $true
    $p2 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '自证进得去 → 理智全刷活动代币关' ($p2.Mode -eq 'event' -and $p2.Stage -eq 'AI-8' -and $p2.ClearSanity) $p2.Reason
    Check '已自证的提示语点名「今天已自证进得去 AI-8」' ($p2.Reason -match '今天已自证进得去 AI-8') $p2.Reason
    Set-FakeArkProbe -Date $today -Entered $false -Evidence '假数据：MAA 的关卡名单里 3 关没有 AI-8'
    $p3 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '自证进不去 → event-pending 且当日改刷长草计划' ($p3.Mode -eq 'event-pending' -and $p3.Stage -eq $idleStage -and $p3.ClearSanity) "stage=$($p3.Stage)"
    Check '进不去的提示语说明被剪/不空试/下一轮自动切回' (($p3.Reason -match '被 MAA 剪掉') -and ($p3.Reason -match '下一轮自动切回') -and ($p3.Reason -notmatch 'AckArk')) $p3.Reason
    Check '进不去时活动关卡仍在 StageHint(下一轮据此重探)' ($p3.StageHint -eq 'AI-8') $p3.StageHint
    Set-FakeArkProbe -Date (Get-Date).AddDays(-1).ToString('yyyy-MM-dd') -Entered $false
    $p4 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '隔天的旧自证结论不挡门(重新拿最后一关当探针)' ($p4.Mode -eq 'event' -and $p4.Stage -eq 'AI-8') $p4.Reason
    Set-FakeArkProbe -Date $today -Key 'zztest-event9' -Entered $false
    $p5 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '活动代号不符的自证结论不挡门(换活动就得重新自证)' ($p5.Mode -eq 'event' -and $p5.Stage -eq 'AI-8') $p5.Reason
    Clear-FakeArkProbe
    Set-GdShopDoneKey -Game 'ark' -Key 'zztest-event'
    $p6 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '商店领空 → 回落长草计划' ($p6.Mode -eq 'idle' -and $p6.Stage -eq $idleStage -and $p6.ClearSanity -and $p6.ShopDone) $p6.Reason
    $p7 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs -IgnoreShopDone
    Check 'IgnoreShopDone 可回看原结论' ($p7.Mode -eq 'event' -and $p7.EventKey -eq 'zztest-event')
    Check '领空后仍能报出活动 id(供撤销)' ($p6.EventKey -eq 'zztest-event') $p6.EventKey
    Check '领空回落的提示语不再带 verb 名(10-30 B-3②-d 刀① 摘掉 body 两枚键，反向钉：出现即红)' (($p6.Reason -notmatch 'daily-clear') -and ($p6.Reason -match '剩余理智改刷长草计划')) $p6.Reason
    $S.ark | Add-Member -NotePropertyName shopDoneStopsEvent -NotePropertyValue $false -Force
    $p8 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '开关置 false 后不再拦截' ($p8.Mode -eq 'event')
    $S.ark | Add-Member -NotePropertyName shopDoneStopsEvent -NotePropertyValue $true -Force
    $q1 = Resolve-ArkPlan -S $S -Data $two -Source '假数据' -Now $nowMs
    Check 'A 已领空 → 转到还没自证的 B 并以 B 的最后一关当探针' ($q1.Mode -eq 'event' -and $q1.EventKey -eq 'zztest-event2' -and $q1.Reason -match '领空') $q1.Reason
    Set-FakeArkProbe -Date $today -Key 'zztest-event2' -Stage 'LS-5' -Entered $false
    $q2 = Resolve-ArkPlan -S $S -Data $two -Source '假数据' -Now $nowMs
    Check 'B 自证进不去 → 当日改刷长草，同时仍报出 A 已领空' ($q2.Mode -eq 'event-pending' -and $q2.EventKey -eq 'zztest-event2' -and $q2.Stage -eq $idleStage -and $q2.Reason -match '领空') $q2.Reason
    Set-FakeArkProbe -Date $today -Key 'zztest-event2' -Stage 'LS-5' -Entered $true
    $q3 = Resolve-ArkPlan -S $S -Data $two -Source '假数据' -Now $nowMs
    Check 'B 自证进得去 → 自动改刷 B' ($q3.Mode -eq 'event' -and $q3.EventKey -eq 'zztest-event2' -and $q3.Reason -match '领空') $q3.Reason
    Clear-FakeArkProbe
    Set-GdShopDoneKey -Game 'ark' -Key 'zztest-event2'
    $q4 = Resolve-ArkPlan -S $S -Data $two -Source '假数据' -Now $nowMs
    Check '都领空 → 长草计划' ($q4.Mode -eq 'idle' -and $q4.ShopDone) $q4.Reason
    Check '撤销标记生效' ((Remove-GdShopDoneKey -Game 'ark' -Key 'zztest-event') -and -not (Get-GdShopDoneMap -Game 'ark').ContainsKey('zztest-event'))
} finally {
    Restore-GdTestState
}
Check 'state 文件已还原' (Test-GdTestStateRestored)

Write-Host "`n[t8] 提权闸门(纯本地，不弹 UAC)"
Check 'Test-GdAdmin 返回布尔' ((Test-GdAdmin) -is [bool]) "当前=$(Test-GdAdmin)"
$bound = @{ Games = 'ark'; Tag = 'auto'; DryRun = $true; Force = [switch]::new($true); SkipCleanup = [switch]::new($false); ArkStage = 'CE-5,LS-5' }
$ra = Get-GdRelaunchArgList -Script 'C:\daily-clear.ps1' -Bound $bound -Force @('-NoElevate')
$joined = $ra -join ' '
Check '重启参数含 -File + 脚本路径' ($ra[3] -eq '-File' -and $ra[4] -like '*daily-clear.ps1*') ($ra[0..4] -join ' ')
Check '重启参数转发字符串参数' ($joined -match '-Games "ark"' -and $joined -match '-ArkStage "CE-5,LS-5"')
Check '重启参数转发已开启的开关' ($joined -match '-Force\b')
Check '未开启的开关不会被带上' ($joined -notmatch '-SkipCleanup')
Check 'DryRun 不会被带上(提权只为真跑)' ($joined -notmatch '-DryRun')
Check 'Force 列表会带上 -NoElevate' ($joined -match '-NoElevate')
Check 'settings 里有提权开关' ($null -ne $S.runtime.arkRequiresElevation) "arkRequiresElevation=$($S.runtime.arkRequiresElevation) arkStartTimeoutMinutes=$($S.runtime.arkStartTimeoutMinutes)"
Check '端游启动超时有配置' ([int]$S.runtime.arkStartTimeoutMinutes -ge 3 -and [int]$S.runtime.arkStartTimeoutMinutes -lt [int]$S.runtime.arkTimeoutMinutes)

Write-Host "`n[t9] 提权载体(Store 版 pwsh 不能直接 RunAs)"
Check 'Get-GdLocalPwsh 不会返回 WindowsApps 路径' ((Get-GdLocalPwsh) -notmatch '\\WindowsApps\\') "本机 pwsh=$(Get-GdLocalPwsh)"
$lineA = Get-GdElevateBatchLine -Pwsh 'C:\Program Files\PowerShell\7\pwsh.exe' -ArgList (Get-GdRelaunchArgList -Script 'C:\my dir\daily-clear.ps1' -Bound @{ Games = 'ark' })
Check '带空格的 pwsh 路径会加引号' ($lineA.StartsWith('"C:\Program Files\PowerShell\7\pwsh.exe" ')) $lineA
Check '批处理一行里 -File 与脚本连在一起' ($lineA -match '-File "C:\\my dir\\daily-clear\.ps1"') $lineA
Check '批处理一行不会被逗号拆散' ($lineA -notmatch '\s"\s' -and $lineA -notmatch '"\s"') $lineA
Check '当前 pwsh 路径可取得' ([bool]((Get-Process -Id $PID).Path)) ((Get-Process -Id $PID).Path)
Write-Host "  提示：Store 版 pwsh 提权会走 cmd.exe 载体(临时批处理)，UAC 上显示的是 cmd.exe" -ForegroundColor DarkGray

Show-GdCommonTailChecks

# 2026-09-23 内部拆分：重试策略跟着"跑一轮"一起搬进了 lib\ark-daily.ps1，入口脚本只剩参数分发；
# 10-24 刀③ 把 ark 那枚 PS 回退臂整段出仓后，这里的桌子跟着换(与 test-r1999 在 刀② 的同形改口同一条纪律)：
# 跳过清单的家在 tools\panel-cs\Orchestration.cs 的 DailyRetry ark 支(verb decide-daily-retry，-Game ark)，
# "重试轮必须重开端游"与"读不到桌面名不许杀正常路"那两条行为的家：5bc83b1 先补尺立进 probe-arkdrive 门的
# retry-stalled／desk-empty 两档，10-27 第十九刀随门整件搬进 main.rs 的 --selftest 第 29 节(见下面六格静态锚)。
# 回退臂出仓后 Start-GdArkDaily 只剩"起内置件走核内驱动档"一条路，探针要桩掉的那条 PS 链已经没有家。
# 断言内容一个字没改——三枚状态名一枚不许少，正则取空窗一律红(fail-closed，不是"读不到就放过")。
$orchArkCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Orchestration.cs') -Raw -Encoding utf8
$arkRetryWin = [regex]::Match($orchArkCs, '(?s)if \(EqS\(game, "ark"\)\)(?<win>.*?)else if \(EqS\(game, "r1999"\)\)').Groups['win'].Value
Check '方舟重试也会跳过 unknown-format' (($arkRetryWin -match '"ok"') -and ($arkRetryWin -match '"not-started"') -and ($arkRetryWin -match '"unknown-format"') -and ($arkRetryWin -match '收尾后重试一次'))
. (Join-Path $PSScriptRoot '..\lib\ark-daily.ps1')   # test-lib 现在按清单把编排层也点进来了(2026-09-26)；这条留着只为"工程被裁时这里还能自己点一次"，重复 dot 只是重新定义同名函数，无副作用
# 2026-09-24 06:00 那一坑(重试前先 Stop-MaaAndGame 把端游也关了，而"拉端游"那句写在重试闭包外面 ⇒ 重试那轮
# 只有 MAA 起来、游戏没起来，白烧一轮)与 2026-09-26 那两条桌面分支(屏保占住 → not-started 早退、一个端游不拉；
# 桌面名读不到 '' = 不知道 → 不许据此杀正常路)：判据的家在 5bc83b1 补进 probe-arkdrive 门的 retry-stalled／
# desk-empty 两档，两代各拍"拉端游两次且 stop#1<launch#2<run#2"与"读不到桌面名仍照常拉起"；那两枚假函数探针
# 只能拍 PS 一代，等值面拍不到"两代一起漏一次 launch"，所以当年补尺先于删件、删的是臂不是判据。
# 2026-10-27 甲档第十九刀：这座等值门(1,014 行／39 格)整件退役——两档两格的行为判据逐格搬进
# tools\rustcore\src\main.rs 的 --selftest 第 29 节(三会话差一枚替身/ctx 的 C-retry-relaunch、早退支与继续支
# 第一次成对的 C-desk-empty-vs-early，另有 mark 双元素与 obsrec Found=false 两半边)，随门死的是 H0 脚手架 12 枚
# 与等值面 21 枚；搬家与 mutation 归因的账见 docs\rust-core-plan.md §11.161/§11.162。
# 这里自此只留"搬过去的尺还在不在"这一类格子：被人删掉时本套件当场红，而不是静默少一条判据。
# ⚠ 推仓 51 那笔把这一格分成三档各判各的，是因为门件按口径不出仓(publish-split 只放 tools\rustcore 的
# build.ps1/Cargo*/src，等值门要 git 工作树与双代 gdcore，玩家树里既没那把尺也没造尺的料)。今天读的两份
# ——lib\ark-daily.ps1 与 tools\rustcore\src\main.rs——三棵树都在场，所以合回无条件一档：判据没放宽，
# 只是"跳过"那一形不再有对象。四格形状照 test-r1999 在 第十六刀 立的静态锚。
$arkDrivePs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\ark-daily.ps1') -Raw -Encoding utf8
$arkCoreRs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rustcore\src\main.rs') -Raw -Encoding utf8
$arkVisionCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Vision.SelfTest.cs') -Raw -Encoding utf8
Check 'arkdrive 门两档的行为判据已在核内 --selftest 第 29 节(门退役后尺住在代码里)' (
    ($arkCoreRs.Contains('第 29 节：arkdrive 门退役四组真空档补尺')) -and ($arkCoreRs.Contains('C-retry-relaunch')) -and
    ($arkCoreRs.Contains('C-desk-empty-vs-early')))
Check 'ark executor 的 ask 白名单仍是十一枚(与核内 DriveFx 动作名逐字同源，改一侧必改另一侧)' ($arkDrivePs.Contains("@('desk', 'svdetail', 'takeover', 'cfg', 'entryverb', 'launch', 'stop', 'sleep', 'skip', 'ledger', 'obs')"))
Check 'ark executor 里没有复活 run／mark／obsrec／admin 任一枚 case(双删是回归抓器：四枚全在核内真做)' (
    (-not $arkDrivePs.Contains("'run' {")) -and (-not $arkDrivePs.Contains("'mark' {")) -and
    (-not $arkDrivePs.Contains("'obsrec' {")) -and (-not $arkDrivePs.Contains("'admin' {")))
Check 'ark 那一路的信封 role 字面仍在(壳认账本是谁的；门里那枚校验随门一起没了)' ($arkDrivePs.Contains('R3-drive-ark-daily'))
# ctx 的**写侧**半边(门 :825 那句「逐枚点名取键那条硬约束就在这里验收」)：读侧取值由 --selftest 第 20 节钉，
# 这里钉的是壳往 ctx 里塞了什么——runtime 那七枚必须逐枚点名取，而整块 $S.runtime 里住着视觉兜底的 API key，
# 所以 ark-daily.ps1 全文不许出现那枚键名(出现＝有人把整块序列化进账)。
Check 'ctx 的 runtime 七枚仍逐枚点名取键(不整块序列化 $S.runtime)' (
    ($arkDrivePs.Contains('[int]$S.runtime.arkStartTimeoutMinutes')) -and ($arkDrivePs.Contains('[int]$S.runtime.arkTimeoutMinutes')) -and
    ($arkDrivePs.Contains('[int]$S.runtime.stallTimeoutMinutes')) -and ($arkDrivePs.Contains('[int]$S.runtime.idleConfirmSeconds')) -and
    ($arkDrivePs.Contains('[bool]$S.runtime.abortOnMaaStallWarning')) -and ($arkDrivePs.Contains('[int]$S.runtime.visionMaxRescue')) -and
    ($arkDrivePs.Contains('benignMaaErrors')) -and ($arkDrivePs.Contains('= $benignMaa')))
Check 'ark 壳侧一个字都不碰视觉 API key(visionApiKey 不许进 ctx/journal 那两本留盘的账)' (-not $arkDrivePs.Contains('visionApiKey'))
# 2026-10-27 甲档第四刀刀②：Invoke-MaaRun 真身(lib\maa.ps1 旧 :220-620)整函数出仓——
# 循环骨架进核(maa_run + RealHost，tools\rustcore\src\main.rs)，判据/话术唯一事实源在
# tools\panel-cs\RunLoops.cs／Orchestration.cs。原咬壳内字面的那批格随壳侧退役：
# unknown-format／asstHint 停滞线索拼装／rescue 三笔账与 -Context／stuckExec 早退与 #17 早触发块序／
# drained 认错收尾与跑空兜底块——对面金样 = panel-cs --looptest(基线钉 c498da0)与
# tools\rustcore\src\main.rs 的 --selftest 第 30 节(27 档 1218 步金样回放)。
# 2026-10-27 甲档第二十刀刀②：那座三侧等值门(probe-arkrun-rust-golden.ps1，1,671 行／13 格)整件退役——
# 真空档 H1/H2/H3/H5/H6 共 155 枚已随刀① 搬进第 30 节，随门死的是 H0 脚手架七枚与 H4(PS 老编排那一侧
# 的等值面，对面已随刀③ 一起没)；搬家与六发 mutation 归因的账见 docs\rust-core-plan.md §11.163/§11.164。
# 形状照第十九刀：这里自此只留"搬过去的尺还在不在"这一类无条件静态锚，被人删掉时本套件当场红。
Check 'arkrun 门 27 档等值面已在核内 --selftest 第 30 节(门退役后尺住在代码里)' (
    ($arkCoreRs.Contains('30. arkrun 27 档金样回放')) -and ($arkCoreRs.Contains('K20_GOLDEN')) -and
    ($arkCoreRs.Contains('K20_EXTRA')))
Check '第 30 节的名册与形状是两份独立事实源(不从金样反推＝第十五刀那条恒真尺防线)' (
    ($arkCoreRs.Contains('const K20_NAMES: [&str; 27] = [')) -and ($arkCoreRs.Contains('const K20_VERBS: [&str; 14] = [')) -and
    ($arkCoreRs.Contains('K20_SHAPE')))
# 2026-10-28 甲档第二十刀刀③：lib\vision-rescue.ps1 的兜底编排六枚(Invoke-GdVisionRescue 及其三枚族内助手
# New-GdRescueSkip/Clear-GdRescueShotDir/Get-GdRescueLedgerPath ＋两枚壳 Test-GdShotChanged/Add-GdRescueRecord，
# 169 函数行)整件出仓，对面随门死的那部分不再重立；t13/t16 那 20 枚随壳侧退役，搬家账见 §11.165。
# 这里照第十九刀留三枚无条件静态锚：一枚"退役不回潮"(有人把六枚定义搬回来就当场红)，两枚"搬过去的尺还在"。
$visionRescuePs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\vision-rescue.ps1') -Raw -Encoding utf8
Check '兜底编排六枚的定义不在现树 PS 侧(双删是回归抓器：编排只住核内 vision_rescue 一处)' (
    (-not $visionRescuePs.Contains('function Invoke-GdVisionRescue ')) -and
    (-not $visionRescuePs.Contains('function New-GdRescueSkip ')) -and
    (-not $visionRescuePs.Contains('function Clear-GdRescueShotDir ')) -and
    (-not $visionRescuePs.Contains('function Get-GdRescueLedgerPath ')) -and
    (-not $visionRescuePs.Contains('function Test-GdShotChanged ')) -and
    (-not $visionRescuePs.Contains('function Add-GdRescueRecord ')))
Check '刀③ 补尺两枚住在核内第 19 节(链不记帐 / context 原样递到问价层)' (
    ($arkCoreRs.Contains('第二十刀刀③ 补尺①')) -and ($arkCoreRs.Contains('第二十刀刀③ 补尺②')))
Check '画面变没变的四形与 detail 压平两形住在 C# 自检里(Vision.SelfTest.cs 接守 t13/t16 摘下的那两族)' (
    ($arkVisionCs.Contains('只有一格抖 1 档')) -and ($arkVisionCs.Contains('两次画面格数不同')) -and
    ($arkVisionCs.Contains('detail 换行压平')))

Write-Host "`n[t12] asst.log 停滞线索(gui.log 静默时唯一看得见的东西)"
# 2026-09-24 18:00 那轮：gui.log 22 分钟一个字没有，asst.log 里 StartUp@GameStart 的 exec_times 从 1 涨到 316。
# 断言用的是当晚日志的真实片段(去掉无关字段)，这样 MAA 改了行格式会立刻在这里红，而不是又在当晚才发现。
$asstExcerpt = @'
[2026-09-24 18:23:26.192][INF][Px29472][Tx36949] {"class":"asst::ProcessTask","cur_task":"StartUp@GameStart","details":{"cur_retry":0,"retry_times":50,"to_be_recognized":["StartUp@GameStart"]},"taskchain":"StartUp","taskid":0}
[2026-09-24 18:23:26.320][INF][Px29472][Tx36949] Assistant::append_callback | SubTaskStart {"class":"asst::ProcessTask","details":{"action":"ClickSelf","algorithm":"MatchTemplate","exec_times":316,"max_times":2147483647,"result":{"rect":[611,652,58,58],"score":0.991275,"template":"GameStart.png"},"task":"GameStart"},"subtask":"ProcessTask","taskchain":"StartUp","taskid":0}
[2026-09-24 18:23:26.320][TRC][Px29472][Tx36949] Win32Controller click: (629, 701)
'@
$asstHint = Get-MaaAsstStuckHint -Text $asstExcerpt
Check '能点名卡住的子任务 + 重复次数 + 最后点击位置' (
    $asstHint -match 'StartUp@GameStart' -and $asstHint -match '316' -and $asstHint -match '629,701') $asstHint
Check '认不出任务时不给线索(不编造)' ((Get-MaaAsstStuckHint -Text '[INF] asst::Controller::connect 123') -eq '')
Check '空文本不炸' ((Get-MaaAsstStuckHint -Text '') -eq '')
# 只点了一两次 = 正常推进，不该跟着喊"被挡住了"(那条结论只在反复点同一处时才成立)
$justOne = Get-MaaAsstStuckHint -Text (@'
{"cur_task":"RecruitBegin","details":{"cur_retry":0,"retry_times":50}}
SubTaskStart {"details":{"exec_times":1,"task":"RecruitBegin"}}
Win32Controller click: (400, 300)
'@)
Check '刚开始的子任务不会被说成"反复点击而界面不动"' (
    $justOne -match 'RecruitBegin' -and $justOne -notmatch '反复点击') $justOne
# 老配置没这个键也要能跑：路径有默认值，且判定不依赖它
# 复制用 Convert-GdMapToHashtable，不要写成 "$S" + 块名 + ".PSObject.Properties" 那种属性展开：
# 导出闸门 Test-GdTemplateCoversCode 是按 $S.<块>.<键> 的字面量扫代码的(连注释一起扫)，
# 展开写法会被它当成"这一路要用 PSObject 这个设置键"，于是模板覆盖率那条检查白红一次。
$pathsNoAsst = Convert-GdMapToHashtable $S.paths
$pathsNoAsst.Remove('maaAsstLog') | Out-Null
$pathsCopy = [pscustomobject]$pathsNoAsst
Check 'settings 缺 maaAsstLog 时路径仍有默认值(debug\asst.log)' (
    (Get-MaaPaths -S ([pscustomobject]@{ paths = $pathsCopy })).AsstLog -match 'debug\\asst\.log$') `
    (Get-MaaPaths -S ([pscustomobject]@{ paths = $pathsCopy })).AsstLog
$liveAsst = (Get-MaaPaths -S $S).AsstLog
if (Test-Path -LiteralPath $liveAsst) {
    Write-Host "  本机 asst.log 末尾现况：$(Get-MaaAsstStuckHint -Text ((Get-Content -LiteralPath $liveAsst -Tail 800 -Encoding utf8) -join "`n"))" -ForegroundColor DarkGray
}

Write-Host "`n[t13] 视觉兜底(全程不联网、不截图、不点任何东西)"
if (Get-Command Get-GdVisionVerdictFromText -ErrorAction SilentlyContinue) {
    $v1 = Get-GdVisionVerdictFromText -Text '{"blocking":true,"what":"中秋活动弹窗","clicks":[{"x":912,"y":233,"why":"右上角关闭"}]}'
    Check '模型按格式回 → 解析出弹窗与坐标' (
        $v1.Blocking -and $v1.What -match '弹窗' -and [int]$v1.X -eq 912 -and [int]$v1.Y -eq 233) "$($v1.What) ($($v1.X),$($v1.Y))"
    # 样本用单引号拼：双引号里的反引号是转义符，``` 三个连写会把行尾的引号吃掉
    $v2Lines = @(
        '好的，我看了一下：'
        '```json'
        '{"blocking":true,"what":"公告","clicks":[{"x":80,"y":90,"why":"知道了"}]}'
        '```'
    )
    $v2 = Get-GdVisionVerdictFromText -Text ($v2Lines -join "`n")
    $v2Info = if ($v2) { "($($v2.X),$($v2.Y)) $($v2.What)" } else { '没解析出来' }
    Check '裹了 markdown 代码块和一句话也能抠出 JSON' ($v2 -and [int]$v2.X -eq 80) $v2Info
    $v3 = Get-GdVisionVerdictFromText -Text '{"blocking":false,"what":"主界面","clicks":[]}'
    Check '没有弹窗时 blocking=false 且没有坐标' ($v3 -and -not $v3.Blocking -and $null -eq $v3.X) ($v3.What)
    Check '回复不成 JSON 时返回空(不拿猜测当依据)' ($null -eq (Get-GdVisionVerdictFromText -Text '我看有个弹窗，你点右上角试试'))
    Check '空回复不炸' ($null -eq (Get-GdVisionVerdictFromText -Text ''))
    $sp = Get-GdVisionSystemPrompt
    Check '提示词还要求"只回 JSON + 千分比坐标"' ($sp -match '只输出一个 JSON' -and $sp -match '千分比')
    # 端点归一化：从控制台复制的"基础地址"多以 /v1 结尾，直接 POST 会 404，而 404 看起来像"模型不可用"。
    Check '基础地址以 /v1 结尾会补成 /chat/completions(末尾多几个斜杠也一样)' (
        (Resolve-GdVisionEndpoint -Base 'https://example.com/compatible-mode/v1/') -eq
        'https://example.com/compatible-mode/v1/chat/completions')
    Check '已经写全的地址不会再被补第二个 /chat/completions' (
        (Resolve-GdVisionEndpoint -Base 'https://example.com/compatible-mode/v1/chat/completions') -eq
        'https://example.com/compatible-mode/v1/chat/completions')
    Check '地址留空回落到百炼公共端点' (
        (Resolve-GdVisionEndpoint -Base '') -eq 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions')
    Check '提示词还禁止点领取/前往参与这类推进状态的按钮' ($sp -match '领取' -and $sp -match '不要给')
    # 2026-09-26：一次只给一个点位时，"点完画面没动"就只能整轮放弃；改成最多 3 个按把握排序的备选，
    # 同一次问价里连着试(实测模型认得弹窗、却把 × 认成相邻的"暂不查看"，第二三个点位就是留给这种错的)。
    Check '提示词允许最多 3 个候选点位，并要求按把握从大到小排' (
        $sp -match 'clicks 最多 3 个' -and $sp -match '把握' -and $sp -notmatch 'clicks 最多 1 个')
    Check '提示词仍把"只会关掉弹窗"当作唯一的点位性质' ($sp -match '关闭/取消/暂不/跳过/知道了')
    # -AllowReward 是第 3 条规则的可选口子(默认关，要玩家在面板里明写勾选)。
    # 两条分支都要判：只判默认分支的话，"勾一下就变成什么都能点"没人拦得住。
    $spAllow = Get-GdVisionSystemPrompt -AllowReward $true
    Check '勾了领奖档 → 允许给出明确的领取按钮' ($spAllow -match '已允许"领取日常奖励"' -and $spAllow -notmatch '绝对不要给"领取"')
    Check '但领奖档仍然禁止花钱/推进进度那类按钮(充值、前往参与、开始行动、确定)' (
        $spAllow -match '充值' -and $spAllow -match '前往参与' -and $spAllow -match '开始行动' -and $spAllow -match '绝对不给')
    Check '领奖档不许改动其余规则(3 个点位/千分比/拿不准给空数组一样都在)' (
        $spAllow -match 'clicks 最多 3 个' -and $spAllow -match '千分比' -and $spAllow -match '拿不准也一律给空数组')
    Check '不勾就是硬禁：默认文案里"领取"和"不要给"绑在同一句(逐字不许变，改了要连配置页文案一起改)' (
        $sp -match '绝对不要给"领取"' -and ($sp -split "`n" | Where-Object { $_ -match '绝对不要给"领取"' }).Count -eq 1)

    # 点位数组：坏点位单独丢掉，不能把同批的好点位一起带走(模型常给 {"x":null})
    $vMany = Get-GdVisionVerdictFromText -Text '{"blocking":true,"what":"公告","clicks":[{"x":null,"y":null,"why":"没坐标"},{"x":700,"y":200,"why":"右上角关闭"},{"x":"abc","y":300,"why":"不是数"},{"x":800,"y":210,"why":"备用"},{"x":900,"y":220,"why":"备用2"},{"x":950,"y":230,"why":"超标的第4个"}]}'
    Check 'Clicks 只留 x/y 真是整数的那几个，最多 3 个' (
        @($vMany.Clicks).Count -eq 3 -and [int]$vMany.Clicks[0].X -eq 700 -and [int]$vMany.Clicks[1].X -eq 800) $(
        (@($vMany.Clicks) | ForEach-Object { "$($_.X),$($_.Y)" }) -join ' / ')
    Check 'X/Y/Why 恒等于第 1 个点位(老代码与 t13 那批断言认的还是这三个字段)' (
        [int]$vMany.X -eq 700 -and [int]$vMany.Y -eq 200 -and $vMany.Why -match '关闭') "$($vMany.X),$($vMany.Y) $($vMany.Why)"
    Check '点位全坏时 Clicks 是空数组、X 为空(不拿猜测当依据)' (
        (@((Get-GdVisionVerdictFromText -Text '{"blocking":true,"what":"x","clicks":[{"x":null,"y":null}]}').Clicks).Count -eq 0) -and
        $null -eq (Get-GdVisionVerdictFromText -Text '{"blocking":true,"what":"x","clicks":[{"x":null,"y":null}]}').X)

    # 1920x1080 的整窗位图：客户区左上角在位图里是 (8,31)，客户区 1904x1041
    $shot = [pscustomobject]@{ ImgW = 1920; ImgH = 1080; ClientLeft = 8; ClientTop = 31; ClientW = 1904; ClientH = 1041 }
    function vd($x, $y) { return [pscustomobject]@{ X = $x; Y = $y } }
    $p1 = Get-GdRescueClickPoint -Shot $shot -Verdict (vd 500 500)
    Check '千分比 → 客户区坐标(要减掉标题栏/边框原点)' ($p1 -and $p1.ClientX -eq 952 -and $p1.ClientY -eq 509) $(
        if ($p1) { "($($p1.ClientX),$($p1.ClientY))" } else { '被拒了' })
    Check '指到标题栏上会被拒(不给越界点击)' ($null -eq (Get-GdRescueClickPoint -Shot $shot -Verdict (vd 500 10)))
    Check '模型没给坐标时不给点击点' ($null -eq (Get-GdRescueClickPoint -Shot $shot -Verdict (vd $null $null)))
    Check '坐标超出 0-1000 视为胡说，拒掉' ($null -eq (Get-GdRescueClickPoint -Shot $shot -Verdict (vd 5000 5)))
    Check '点右下角最后一个像素也算越界' (
        $null -eq (Get-GdRescueClickPoint -Shot $shot -Verdict (vd 1000 1000)))

    # 2026-10-28 甲档第二十刀刀③：本节原咬 Test-GdShotChanged 转发壳的四发实跑(同图/单格抖/整块暗/没签名)
    # 随壳出仓退役。"点完画面到底变没变必须用粗亮度签名、不能用文件哈希"这条判据没跟着消失：四形现由
    # panel-cs --visiontest 接守(Vision.SelfTest.cs:279-306，含"两次画面格数不同→说不清别硬判"那形)，
    # 阈值为什么是"≥2 格、每格 ≥3 档"记在 Vision.cs 的 shot-changed 段，核内消费点另有第 19 节
    # 「点了但画面没变」那一格钉话术($chg.Detail 出现两次的原样怪癖)。
    $fnShot = (Get-Command Save-GdWindowShot).Definition
    $fnClick = (Get-Command Send-GdArkClick).Definition
    Check '截图函数会带回 Sig(不然"画面变没变"那一路全是瞎的)' ($fnShot -match 'Sig = ')
    Check '点击走"抢前台 + 真实鼠标"，PostMessage 只当退路' (
        $fnClick -match 'TryForeground' -and $fnClick -match 'RealClick' -and $fnClick -match 'ClickOnce')
    # 2026-10-26 起兜底内核不认识端游了：截图/点击都向靶子要(lib\vision-ark.ps1 的 New-GdVisionTarget-ark)。
    # 编排层那半"内核里不能再出现端游那三个动作"随 Invoke-GdVisionRescue 出仓，判据改由 Rust 第 19/30 节的
    # 现场 verb 名册接守(ark 两枚 ark-window-shot/ark-window-click)；这里判的还是另一头——靶子必须把
    # Shot/Click 接到端游那两枚真件上，接不上就是"兜底静默不生效"。
    $fnTarget = (Get-Command New-GdVisionTarget-ark).Definition
    Check '端游靶子把 Shot/Click 接到 Save-GdWindowShot / Send-GdArkClick 上' (
        $fnTarget -match 'Save-GdWindowShot' -and $fnTarget -match 'Send-GdArkClick')
    Check '最小化的窗口会先 SW_RESTORE 再拍(否则拍到的是 168x29 空位图)' (
        $fnShot -match 'IsIconic' -and $fnShot -match 'Restore')
    # 2026-10-28 甲档第二十刀刀③：本节原有两枚真跑格("arkVisionRescue=false 一次都不试"与"没提权或没 key
    # 直接放弃")随编排壳退役。开关话术必须带 settings 键名这条判据没丢，它在 C# 那侧由 --livetest
    # 两格钉住(Live.SelfTest.cs:137/174 认 'arkVisionRescue=false，视觉兜底已关闭')；闸门顺序(Python 排在
    # 截图之前)现由核内投影序钉住(第 19 节 rescue-ok 的 resolve-rescue-context 排在 ark-window-shot 之前)。
    # 多候选循环那三格(逐个试/先剔越界/全灭话术)与"账本由调用方点""-Context 递到问价层"两格一并出仓，
    # 前者在第 30 节 ark 27 档金样里有原样的步序，后两枚是本刀新立的第 19 节补尺两格(见 --selftest)。
    $fnRaw = (Get-Command Invoke-GdVisionRaw).Definition
    Check '问价那一层把自动化的处境拼进用户那句话，并且截到 200 字(不塞日志原文)' (
        $fnRaw -match '自动化这边的处境' -and $fnRaw -match '200')
    # 2026-10-28 甲档第二十二刀：这里原有那枚「-Context 从问价壳递到起子进程那层」随 Invoke-GdVisionAsk 壳
    # 出仓退役(它唯一吃的 $fnAsk 没了对面)；判据现只住核内补尺②——main.rs 第 19 节钉的是 context 的值本身到了。
} else {
    Check 'lib\vision-rescue.ps1 存在(方舟仓库少了它兜底就不生效)' $false '没找到 Get-GdVisionVerdictFromText'
}

Write-Host "`n[t14] 点了没动怎么说、怎么早退(2026-09-25 一天里两次改口的教训都在这里)"
# 06:00 那轮的真凭据：MAA 每 4 秒往 splash 的 START 点一下、点到 exec_times=311，模板分始终 0.99，画面一动不动。
# 早上第一版把原因写成"MAA 抢不到前台退化成 PostMessage，而端游不吃"，依据是"成功轮每小时 174 条
# inject_input_event、失败轮一条都没有"。那个依据是数错日志：把整份 asst.log 按动作归类之后，
# 全部 2001 次注入都来自同一个子任务 SwipeToTheLeft(基建向左滑)，而 7640 次 ClickSelf / 719 次 ClickRect
# 一条注入都没有 —— 点击在成功轮里也一直是配置里那个发消息方式。所以：注入只能说明"滑过基建没有"，
# 绝不能拿来当"点击通道活没活"的判据；早退改按"同一个子任务重试到第几次"判。
$asstDead = @'
{"cur_task":"StartUp@GameStart","details":{"cur_retry":0,"retry_times":50}}
SubTaskStart {"details":{"exec_times":269,"task":"GameStart"}}
Win32Controller click: (643, 666)
Win32Controller click: (647, 670)
Win32Controller click: (638, 663)
'@
$stDead = Get-MaaAsstStuckState -Text $asstDead
Check '状态里四个数都数得到(任务/重试到第几/点击行/注入行)' (
    $stDead.Task -eq 'StartUp@GameStart' -and $stDead.Exec -eq 269 -and $stDead.Clicks -eq 3 -and $stDead.Inject -eq 0) $(
    "$($stDead.Task) exec=$($stDead.Exec) clicks=$($stDead.Clicks) inject=$($stDead.Inject)")
$asstSwipe = @'
{"cur_task":"InfrastTimePhase","details":{"cur_retry":0,"retry_times":5}}
SubTaskStart {"details":{"exec_times":1,"action":"Swipe","task":"SwipeToTheLeft"}}
asst::Win32Controller::inject_input_event | enter
asst::Win32Controller::inject_input_event | leave, 14 ms
asst::Win32Controller::inject_input_event | enter
'@
$stSwipe = Get-MaaAsstStuckState -Text $asstSwipe
Check '注入行只在滑动类子任务里出现，数得到就不等于"点击通道活着"' (
    $stSwipe.Task -eq 'InfrastTimePhase' -and $stSwipe.Inject -eq 2 -and $stSwipe.Clicks -eq 0) $(
    "task=$($stSwipe.Task) inject=$($stSwipe.Inject) clicks=$($stSwipe.Clicks)")
$hintDead = Get-MaaAsstStuckHint -Text $asstDead
Check '点了没动时两种可能都留着，不再把某个原因写成定论' (
    $hintDead -match '窗口挡' -and $hintDead -match '前台|会话') $hintDead
Check '结论里不出现"通道退化/不吃 PostMessage"那句(它已被证伪)' (
    $hintDead -notmatch '通道退化' -and $hintDead -notmatch '不吃 PostMessage' -and $hintDead -notmatch '八成是') $hintDead
Check '任务名/重试次数/最后点击位置三个字段照常带上' (
    $hintDead -match 'StartUp@GameStart' -and $hintDead -match '269' -and $hintDead -match '638,663')
Check '空片段不给状态、也不给结论' (
    (-not (Get-MaaAsstStuckState -Text '').Task) -and ((Get-MaaAsstStuckHint -Text '') -eq ''))
# 探测函数：纯读，不动窗口、不点东西。锁屏与否按"输入桌面叫什么"判，读不到就说读不到(别把未知说成锁屏)。
if (Get-Command Get-GdArkDesktopState -ErrorAction SilentlyContinue) {
    $st = Get-GdArkDesktopState -Hwnd $null
    Check '探测会报出输入桌面(未锁屏=Default)' ($st.Detail -match '输入桌面=') $st.Detail
    Check '桌面名读不到时 Locked 给"不知道"而不是"锁屏了"' (
        ($null -eq $st.Locked) -or ($st.Locked -eq ($st.Desktop -ne 'Default'))) "Desktop=[$($st.Desktop)] Locked=$($st.Locked)"
    Check '没给窗口句柄时明说"端游窗口没找到"' ($st.Detail -match '端游窗口没找到')
    # 光标位置在"会话不在正常输入桌面"(锁屏 / Screen-saver 桌面)时本来就读不到 —— 那种情况下探测会明说
    # "会话不在正常桌面"，这算它说对了，不该记红。这套自检标榜"只读、不启动任何程序"，
    # 所以它也不能要求"跑的时候屏幕是亮着没锁的"(2026-09-25 验收链就在锁屏的机器上红过这一条)。
    Check '探测顺手记下光标位置(判"这一轮鼠标进不进得来"的现场量)；不在正常桌面时改成说清为什么读不到' (
        $st.Detail -match '光标在 ' -or ($st.Desktop -ne 'Default' -and $st.Detail -match '不在正常桌面')) $st.Detail
    $fnGrab = (Get-Command Invoke-GdArkForegroundGrab).Definition
    # B0(2026-09-29)：这二十来个 user32 签名不再内联在 lib\vision-ark.ps1 的 here-string 里，逐字搬进
    # tools\gdinterop\GdWin.cs 由 Add-GdInterop 现编 —— 下面两条钉名单的断言随之改读那份 .cs 的文本。
    # 第一条把"名单只在 GdWin.cs 里"钉成同一件事：vision-ark 若还留着 Add-Type -TypeDefinition，
    # 两个宿主会当场抛"类型名称 GdWin 已存在"(2026-09-29 实测)，所以它同时是"迁移有没有做一半"的门。
    $gdWinCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\tools\gdinterop\GdWin.cs') -Raw -Encoding utf8
    $arkVisionTxt = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\vision-ark.ps1') -Raw -Encoding utf8
    Check '桌面名走 OpenInputDesktop + UOI_NAME，用完关掉句柄(名单只在 tools\gdinterop\GdWin.cs 里)' (
        $gdWinCs -match 'OpenInputDesktop' -and $gdWinCs -match 'GetUserObjectInformationW' -and
        $gdWinCs -match 'CloseDesktop' -and $arkVisionTxt -notmatch 'Add-Type -TypeDefinition') `
        ("GdWin.cs={0} 字符 / vision-ark 仍内联 C#={1}" -f $gdWinCs.Length, ($arkVisionTxt -match 'TypeDefinition'))
    Check '探测还能说清"谁占着前台"，并且读窗口自身状态(最小化/可见/矩形)' (
        $gdWinCs -match 'GetWindowThreadProcessId' -and $gdWinCs -match 'IsWindowVisible' -and
        $gdWinCs -match 'WindowRectText')
    Check '抢前台只动窗口状态，绝不往客户区点一下，并把现场带回 Detail' (
        $fnGrab -match 'TryForeground' -and $fnGrab -notmatch 'RealClick' -and $fnGrab -notmatch 'ClickOnce' -and
        $fnGrab -match 'st\.Detail')
} else {
    Check 'lib\vision-rescue.ps1 存在(方舟仓库少了它探测就不生效)' $false '没找到 Get-GdArkDesktopState'
}

Write-Host "`n[t15] MAA 自己把队列跑空了，别再傻等 22 分钟(2026-09-25 07:53 那轮现场暴露的)"
# 那一轮 asst.log 里 5 次点击全部落地(START 一点就过、还关掉了两张弹窗)，随后
# StartUp@CloseAnno 连认 50 次认不出「锦枫映月」的 ×，公招/基建/作战/商店/奖励 6 条链路 0 完成，
# 07:56:46 gui.log 打出「任务已完成，但出现错误！」= MAA 的队列已经空了、它不会再自己动。
# 老代码只认「任务已全部完成」，于是这一种收尾一路等到「asst.log 静默 22 分钟」才反应，
# 而那时候就算把挡路窗口关掉也没人接着跑 —— 白等 22 分钟。
# 2026-10-27 甲档第四刀刀②：本节原咬 lib\maa.ps1 壳内字面的六格随 Invoke-MaaRun 出仓退役——
# 「跑完但有错误」认线、$drained 置位、跑空当场兜底一次＋早退 stalled＋外层重试一次的话术与块序，
# 金样现由 panel-cs --looptest 接守(RunLoops.SelfTest.cs：「MAA 队列已跑空但只完成 0/2 条链路…外层会重试一次」族)。

Write-Host "`n[t16] 只问不点的诊断入口(2026-09-26 加强 AI 干预时加的，全程不联网、不起子进程)"
# 2026-10-28 甲档第二十刀刀③：本节原咬 Add-GdRescueRecord 壳的九格(第一次记账不抛 / Test-Path 守卫 /
# 落 state\rescue.json 且一次兜底一行 / 归属由调用方写 / tried-done 两个独立 bool / detail 换行压平 /
# 超 Keep 砍最老 / 写不进只 WARN 不抛 / state 已还原)随壳退役，整节改由下面三处接守——
#   压平那形：panel-cs --visiontest(Vision.SelfTest.cs:351/353，含 \r\n 那半)；
#   读-改-写与"缺文件不许惊动 WARN"：--selftest 第 19 节(真写账本文件再读回，version/updated/events 三格
#     ＋ Keep 60 滑窗各一格)，本刀另在该节补两枚(链自己不许记帐 / context 原样递到问价层)；
#   名册与形状：--selftest 第 30 节 ark 27 档金样的 H5(六格逐字符)/H6a(条数==rescue-entry 次数)/
#     H6b(version==1 且 game-target-tag-detail 四格越界判)，其余 20 档钉"零账本"。
# 本节因此不再真写 state\rescue.json，Save-GdTestState 那对存/还原也一并撤下(没有要还的盘了)。

# tools\vision-ask.ps1 是"只问不点"的排查入口：配好 key 之后不用跑一轮日常，就能看到模型对着这张图怎么说。
# 它的价值恰恰在于**不动手**，所以这里判的就是"它真的没有点击的手"。
$askPath = Join-Path $PSScriptRoot 'vision-ask.ps1'
if (Test-Path -LiteralPath $askPath) {
    $askSrc = Get-Content -LiteralPath $askPath -Raw -Encoding utf8
    # 注释里写着"唯独不碰 $t.Click"，所以判"它没有点击的手"只能判代码，不能判整份文本 ——
    # 整份文本一起 match 会把那句自我声明当成违规，红得毫无意义。
    $askCode = (($askSrc -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
    Check '只问不点：代码里没有 $t.Click / Send-GdArkClick / adb input tap 任何一种点击出口' (
        $askCode -notmatch '\$t\.Click' -and $askCode -notmatch 'Send-GdArkClick' -and $askCode -notmatch 'input tap')
    Check '复用的是同一套靶子和同一个问价函数(不另写一份提示词，免得两边规则漂移)' (
        $askSrc -match 'Get-GdVisionTarget' -and $askSrc -match 'Invoke-GdVisionRaw')
    Check '跑完当面告诉人"本文件没有点任何东西"' ($askSrc -match '没有点任何东西')
    Check '问哪一路由清单的 VisionKind 决定，这份文件里没有 ark/mumu 硬对照表' (
        $askSrc -match 'VisionKind' -and $askSrc -notmatch "=\s*'mumu'")
    Check '给了 -Image 就直接用那张图(不截图，也不会因为后端不在就放弃)' ($askSrc -match '\$Image')
    Check '开关关着/没提权/对象不在时只说人话，不硬拍' (
        $askSrc -match 't\.Enabled' -and $askSrc -match 'AdminWhy' -and $askSrc -match 't\.Alive')
} else {
    Check 'tools\vision-ask.ps1 存在(只问不点的诊断入口)' $false '没找到这份文件'
}

Write-Host "`n[farm] 智能补材料(lib\ark-farm.ps1，纯函数喂假数据；IO 只碰临时目录)"
# 这份库由 test-lib 按清单点进来(以前它不在名单里，下面那段记账跑的是"认不到函数→catch→打一句 WARN 就过"的假绿)。
# 文件不在(工程被裁)时交给下面那句守卫说人话，不在这里自己补点。
if (Get-Command Resolve-ArkFarmPlan -ErrorAction SilentlyContinue) {
    # —— 目标清单解析：三种写法 + 坏行不静默 ——
    $p1 = Parse-GdArkFarmTargetSpec -Raw 'D32钢=30@CE-5'
    Check 'farm 目标：名=数@关 拆得开' ($p1.Key -eq 'D32钢' -and $p1.Target -eq 30 -and @($p1.Stages).Count -eq 1 -and -not $p1.Bad) "$($p1.Raw)"
    $p2 = Parse-GdArkFarmTargetSpec -Raw '30135=12@CE-5,CE-4'
    Check 'farm 目标：代号+多关(逗号/顿号分隔)拆得开' ($p2.Key -eq '30135' -and @($p2.Stages).Count -eq 2) ($p2.Stages -join '/')
    $p3 = Parse-GdArkFarmTargetSpec -Raw @{ item = 'D32钢'; target = 20; stages = @('CE-5') }
    Check 'farm 目标：json 对象写法也吃' ($p3.Key -eq 'D32钢' -and $p3.Target -eq 20 -and -not $p3.Bad)
    $p4 = Parse-GdArkFarmTargetSpec -Raw '想刷点火腿'
    Check 'farm 目标：看不懂的行给 Bad 说明而不是丢掉' ([string]$p4.Bad -match '材料名=数量') "[$($p4.Bad)]"
    $p5 = Parse-GdArkFarmTargetSpec -Raw @{ item = 'D32钢' }
    Check 'farm 目标：对象缺数量也给 Bad' ([string]$p5.Bad -match '目标数量')

    # —— 掉落文本解析：形状、拒绝表、只认 (+N) ——
    $sample = @(
        '[08:50:26] CE-5 掉落统计:'
        'D32钢 : 2 (+2)   或铝石 : 1 (+1)   当前次数 : 3'
        '[08:52:10] LS-5 掉落统计:'
        '采购凭证 : 30 (30)'
    ) -join "`r`n"
    $blks = @(Parse-GdArkDropText -Text $sample)
    Check 'farm 掉落：两个块、关卡代号抓得到' ($blks.Count -eq 2 -and $blks[0].Stage -eq 'CE-5' -and $blks[1].Stage -eq 'LS-5') "$($blks.Count) 块"
    Check 'farm 掉落：时间戳前缀不影响识别；「当前次数」被拒绝表挡掉' (@($blks[0].Items).Count -eq 2 -and [string]$blks[0].Items[0].Name -eq 'D32钢') (($blks[0].Items | ForEach-Object { "$($_.Name)+$($_.Delta)" }) -join ' ')
    Check 'farm 掉落：只按 (+N) 记增量，"(30)"这种总数不当增量' (@($blks[1].Items).Count -eq 1 -and [int]$blks[1].Items[0].Delta -eq 0)
    Check 'farm 掉落：空文本给空数组不抛' (@(Parse-GdArkDropText -Text '').Count -eq 0)

    # —— 判表：缺口/选关/封顶/来源标注 ——
    $N2I = @{ 'D32钢' = '30135'; '或铝石' = '30115' }
    $I2N = @{ '30135' = 'D32钢'; '30115' = '或铝石' }
    $known = @{ 'CE-5' = $true; 'CE-4' = $true }
    $r0 = Resolve-ArkFarmPlan -Targets @()
    Check 'farm 判表：空清单不炸参数绑定，理由说"没配 farmTargets"' (-not $r0.Active -and $r0.Reason -match 'farmTargets') $r0.Reason
    $dt = @{ '30135' = @{ 'CE-5' = @{ runs = 5; qty = 12 }; 'CE-4' = @{ runs = 3; qty = 3 } } }
    $rf = Resolve-ArkFarmPlan -Targets @($p1) -NameToId $N2I -IdToName $I2N -Inventory @{ '30135' = 18 } -DropTable $dt -KnownStages $known
    # 目标30 现有18 差12；p1 显式填了 CE-5 → 09-29 保守口径：次数=缺口(每场掉 1 保底、凑满目标为止)，学习均值只进括号报数(12/5=2.4)
    Check 'farm 判表：缺口=目标-现有，学习表挑关(最多2、平均掉得多的打头)' ($rf.Active -and [int]$rf.Gap -eq 12 -and @($rf.Stages).Count -le 2 -and $rf.Stages[0] -eq 'CE-5') ($rf.Stages -join ',')
    Check 'farm 判表：次数按缺口保守折算且 Reason 说清账目' ([int]$rf.Times -eq 12 -and $rf.Reason -match '还差 12' -and $rf.Reason -match '每场约 2\.4') $rf.Reason
    $rc = Resolve-ArkFarmPlan -Targets @(Parse-GdArkFarmTargetSpec -Raw 'D32钢=99@CE-5') -NameToId $N2I -IdToName $I2N -Inventory @{} -DropTable $dt -KnownStages $known -MaxTimes 4
    Check 'farm 判表：单轮封顶生效并在 Reason 里说"明天接着刷"' ([int]$rc.Times -eq 4 -and $rc.Reason -match '单轮封顶 4') $rc.Reason
    $rg = Resolve-ArkFarmPlan -Targets @(Parse-GdArkFarmTargetSpec -Raw 'D32钢=10@CE-5') -NameToId $N2I -IdToName $I2N -Inventory @{ '30135' = 12 } -DropTable $dt
    Check 'farm 判表：已够的目标不刷，理由里带"已够"' (-not $rg.Active -and $rg.Reason -match '已够') $rg.Reason
    $ro = Resolve-ArkFarmPlan -Targets @(Parse-GdArkFarmTargetSpec -Raw '30135=30@CE-9') -NameToId $N2I -IdToName $I2N -Inventory @{} -KnownStages $known
    Check 'farm 判表：只填了不认识的关 → 不刷并说为什么' (-not $ro.Active -and $ro.Reason -match '不被 MAA 关卡表认识') $ro.Reason
    $ru = Resolve-ArkFarmPlan -Targets @(Parse-GdArkFarmTargetSpec -Raw '点火腿=5') -NameToId $N2I -IdToName $I2N
    Check 'farm 判表：材料表查不到的名字跳过并说明(不静默)' (-not $ru.Active -and $ru.Reason -match 'item_index') $ru.Reason
    $rn = Resolve-ArkFarmPlan -Targets @(Parse-GdArkFarmTargetSpec -Raw 'D32钢=5') -NameToId $N2I -IdToName $I2N -Inventory @{} -DropTable @{}
    Check 'farm 判表：没学习数据又没填关 → 提示写成带 @关卡 的形式' (-not $rn.Active -and $rn.Reason -match '@CE-5') $rn.Reason
    $re = Resolve-ArkFarmPlan -Targets @(Parse-GdArkFarmTargetSpec -Raw 'D32钢=8@CE-5') -NameToId $N2I -IdToName $I2N -Inventory @{ '30135' = 4 } -Origin @{ '30135' = 'depot' }
    Check 'farm 判表：depot 标定的现值在 Reason 里明说"是估算"；无学习数据按每场 1 估' ($re.Reason -match '估算' -and $re.Reason -match '按每场 1 估' -and [int]$re.Times -eq 4) $re.Reason
    # 多目标取缺口最大：D32钢差2、或铝石差10 → 应选或铝石
    $rb = Resolve-ArkFarmPlan -Targets @((Parse-GdArkFarmTargetSpec -Raw 'D32钢=20@CE-5'), (Parse-GdArkFarmTargetSpec -Raw '或铝石=100@CE-4')) -NameToId $N2I -IdToName $I2N -Inventory @{ '30135' = 18; '30115' = 90 }
    Check 'farm 判表：多目标一次只锁缺口最大的那个' ($rb.ItemName -eq '或铝石' -and [int]$rb.Gap -eq 10) $rb.Reason

    # —— 材料表(IO)：真实 MAA 目录里 item_index 读得出映射 ——
    $maps = Get-GdArkItemMaps -S $S
    Check 'farm 材料表：MAA item_index 读得出 300+ 条映射' ($maps.NameToId.Count -gt 300) "$($maps.NameToId.Count) 条"

    # —— 账本 IO：临时 state 目录里往返，绝不碰真账本 ——
    $stateBak = $global:GD.State
    $tmpState = Join-Path ([System.IO.Path]::GetTempPath()) ('gd-farmtest-' + $PID)
    New-Item -ItemType Directory -Force -Path $tmpState | Out-Null
    try {
        $global:GD.State = $tmpState
        $empty = Read-GdArkFarmLedger -S $S
        Check 'farm 账本：文件不在就是空账(首跑判定先于记账，不抛)' ($empty.Inventory.byId.Count -eq 0 -and $empty.DropTable.Count -eq 0)
        Write-GdJson -Path (Get-GdArkFarmInventoryPath) -Object ([pscustomobject]@{
            version = 1
            offset  = [pscustomobject]@{ path = 'X:\fake\gui.log'; offset = 4096 }
            byId    = [pscustomobject]@{ '30135' = [pscustomobject]@{ count = 20; origin = 'drops'; updated = '2026-09-26 08:00:00' } }
        })
        Write-GdJson -Path (Get-GdArkFarmDropTablePath) -Object ([pscustomobject]@{
            '30135' = [pscustomobject]@{ 'CE-5' = [pscustomobject]@{ runs = 5; qty = 12 } }
        })
        $led2 = Read-GdArkFarmLedger -S $S
        Check 'farm 账本：写入后读回的契约是 hashtable 且数字没丢' (
            ($led2.Inventory.byId -is [System.Collections.IDictionary]) -and [int]$led2.Inventory.byId['30135'] -eq 20 -and
            [int]$led2.DropTable['30135']['CE-5'].qty -eq 12)
        Check 'farm 账本：偏移按 {path;offset} 成对存(换日志文件不回扫旧账)' (
            [string]$led2.Inventory.offset.path -eq 'X:\fake\gui.log' -and [long]$led2.Inventory.offset.offset -eq 4096)

        # —— 记账 IO 端到端(2026-09-26 补)：真函数 Update-GdArkFarmLedger 整段跑一遍 ——
        # 这条以前根本测不了：ark-farm.ps1 不在 test-lib 的点用清单里，ark-daily 收尾那句调用在自检环境里
        # 认不到函数 → 掉进它自己的 catch → 打一句 WARN 就"过"了，全套件仍然全绿(零覆盖的假绿)。
        # 现在名单补齐了，这里用 假 gui.log + 假材料表 + 临时 state 把"读日志→记增量→写偏移"这条真链路钉住。
        # 两本账先写成"文件在但是空账"：文件不在会让它去读真 MAA 目录的 DepotData 做首跑标定，数字就不可押了。
        Write-GdJson -Path (Get-GdArkFarmInventoryPath) -Object ([pscustomobject]@{ version = 1; offset = $null; byId = [pscustomobject]@{} })
        Write-GdJson -Path (Get-GdArkFarmDropTablePath) -Object ([pscustomobject]@{})
        $fakeLog = Join-Path $tmpState 'gui-farm.log'
        # 编码自己钉无 BOM UTF-8：5.1 的 Add-Content/Set-Content -Encoding utf8 会带 BOM，
        # BOM 混在日志中间会被 Get-GdFileTail 当成正文，材料名就认不出来了(那是测试自己的坑，不是被测代码的坑)。
        [System.IO.File]::WriteAllText($fakeLog, ($sample + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        function Invoke-GdFarmLedgerOnce {
            param([string]$Log, $S)
            # 只把 Get-MaaPaths 换成指假日志的桩(和上面重试探针同一招：函数定义在本作用域，按动态作用域盖掉同名函数)
            function Get-MaaPaths { param($S) return [pscustomobject]@{ GuiLog = $Log } }
            return (Update-GdArkFarmLedger -S $S)
        }
        $mapsBak = (Get-Variable -Name GdArkItemMaps -Scope Global -ErrorAction SilentlyContinue).Value
        $global:GdArkItemMaps = @{ NameToId = $N2I; IdToName = $I2N }
        # 真 state 里那份账本先留哈希：整段测试只许碰临时目录，真账本一个字节都不许变
        $realInv = Join-Path $stateBak 'ark-inventory.json'
        $realHashBefore = if (Test-Path -LiteralPath $realInv) { (Get-FileHash -LiteralPath $realInv -Algorithm SHA256).Hash } else { '' }
        try {
            $note1 = Invoke-GdFarmLedgerOnce -Log $fakeLog -S $S
            $led3 = Read-GdArkFarmLedger -S $S
            Check 'farm 记账：真链路跑通，D32钢按 (+2) 入账且来源标 drops' (
                [int]$led3.Inventory.byId['30135'] -eq 2 -and [string]$led3.Inventory.origin['30135'] -eq 'drops') ($note1)
            Check 'farm 记账：同一块里的第二个材料也记上(或铝石 +1)' ([int]$led3.Inventory.byId['30115'] -eq 1)
            Check 'farm 记账：学习表抓到「关卡→材料」关系(CE-5 掉 D32钢 2 个，1 场)' (
                [int]$led3.DropTable['30135']['CE-5'].runs -eq 1 -and [int]$led3.DropTable['30135']['CE-5'].qty -eq 2)
            Check 'farm 记账：只认 (+N)，"(30)"那种总数不入账；认不出的名字进未识别表而不是被丢掉' (
                ([int]$led3.Inventory.byId['30114'] -eq 0 -or -not $led3.Inventory.byId.ContainsKey('30114')) -and
                (@(Read-GdJson -Path (Get-GdArkFarmDropsPath)) -contains '采购凭证'))
            Check 'farm 记账：偏移存成"读到的那个字节数"，落在假日志的真实长度上' (
                [string]$led3.Inventory.offset.path -eq $fakeLog -and
                [long]$led3.Inventory.offset.offset -eq (Get-Item -LiteralPath $fakeLog).Length)
            # 关键回归：同一段日志再跑一遍必须什么都不记(上上轮拿首拍把 7 月的旧完成线扫进过账)
            $note2 = Invoke-GdFarmLedgerOnce -Log $fakeLog -S $S
            $led4 = Read-GdArkFarmLedger -S $S
            Check 'farm 记账：日志没新增就返回空话，绝不回扫旧账' (
                [string]::IsNullOrEmpty([string]$note2) -and [int]$led4.Inventory.byId['30135'] -eq 2) ($note2)
            [System.IO.File]::AppendAllText($fakeLog, "[09:10:00] CE-4 掉落统计:`r`nD32钢 : 5 (+3)`r`n", (New-Object System.Text.UTF8Encoding($false)))
            $note3 = Invoke-GdFarmLedgerOnce -Log $fakeLog -S $S
            $led5 = Read-GdArkFarmLedger -S $S
            Check 'farm 记账：追加一段只吃新增那半(+3 → 5)，旧块不重记' (
                [int]$led5.Inventory.byId['30135'] -eq 5 -and [int]$led5.DropTable['30135']['CE-5'].runs -eq 1 -and
                [int]$led5.DropTable['30135']['CE-4'].runs -eq 1) ($note3)
        } finally {
            if ($null -ne $mapsBak) { $global:GdArkItemMaps = $mapsBak }
        }
        $realHashAfter = if (Test-Path -LiteralPath $realInv) { (Get-FileHash -LiteralPath $realInv -Algorithm SHA256).Hash } else { '' }
        Check 'farm 记账：整段只碰临时目录，真 state 的 ark-inventory.json 一个字节没变' (
            $realHashAfter -eq $realHashBefore) ("before=[$realHashBefore] after=[$realHashAfter]")
    } finally {
        $global:GD.State = $stateBak
        Remove-Item -LiteralPath $tmpState -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Check 'lib\ark-farm.ps1 在场(智能补材料的判定+记账层)' $false '没找到 Resolve-ArkFarmPlan'
}

$res = Show-GdTestResult -Tag 'ark'
if ($NoExit) { return $res }
exit $(if ($res.Fail) { 1 } else { 0 })
