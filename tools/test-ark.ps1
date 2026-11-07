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

# ---- 刀⑯ 笔(d)-1(11-06)静态锚：组值半段"一次取齐"的形状，钉在 maaDir 那道现场门之前 ----
# 为什么放这里：这一格钉的是源码形状，MAA 目录在不在都该有证词(只读自检不许要求机器现场状态)；
# 放在下面那道 return 之后，没配 paths.maaDir 的机器上它就静默不跑，等于把锚做成哑尺。
# 旧三枚 state 读件(Get-GdAckMap／Get-GdShopDoneMap／Get-GdArkEventProbe)与领空 flag 尺 Test-GdShopDoneEnabled
# 本批出仓，锚自此换家到 Resolve-ArkPlan 的组值半段。剥注释照 tools\test-r1999.ps1 那两形(-replace 逐字复用)：
# 不剥注释的"正向锚"会在真身被摘掉后照样绿——那是本仓登记过的"锚不是调用"形。
$fnPlan = [string](Get-Command Resolve-ArkPlan -ErrorAction SilentlyContinue).Definition
$fnPlan = ($fnPlan -replace '(?s)<\#.*?\#>', ' ') -replace '(?m)^\s*#.*$', ' '
Check '刀⑯ 笔(d)-1 核臂在：Resolve-ArkPlan 现问 read-decision-state 一次取齐(ack／领空／自证三枚读件不再各开一把)' (
    $fnPlan.Contains("Invoke-GdCli -Verb 'read-decision-state'") -and
    -not $fnPlan.Contains('Get-GdAckMap') -and -not $fnPlan.Contains('Get-GdShopDoneMap') -and -not $fnPlan.Contains('Test-GdShopDoneEnabled')) $(
    if ($fnPlan.Length -eq 0) { 'Resolve-ArkPlan 不在场(尺没接到电)' } else { "len=$($fnPlan.Length)" })
Check '刀⑯ 笔(d)-1 折算在：领空图给不给吃的是核交回的 ShopDoneGateOpen(PS 侧不再再造一把 flag 尺；IgnoreShopDone 语义仍在)' (
    $fnPlan.Contains('$ds.ShopDoneGateOpen') -and $fnPlan.Contains('$IgnoreShopDone')) $('len=' + $fnPlan.Length)

# 行为级(判据换家的正对照)：核把原表与"给不给"分两枚键交回——ShopDoneGateOpen 不消费原表，
# 领空门折算吃的就是这一枚；旧"语义边界"格(表读件不取 ShopDoneGateOpen)随三枚读件出仓，此格承其位。
$dsGate = Invoke-GdCli -Verb 'read-decision-state' -Body ([pscustomobject]@{ game = 'ark' })
Check '刀⑯ 笔(d)-1 行为锚：read-decision-state 把 ShopDone 原表与 ShopDoneGateOpen"给不给"分两枚键交回(后者是布尔)' (
    ($null -ne $dsGate.PSObject.Properties['ShopDone']) -and
    ($null -ne $dsGate.PSObject.Properties['ShopDoneGateOpen']) -and ($dsGate.ShopDoneGateOpen -is [bool])) $(
    "gate=$($dsGate.ShopDoneGateOpen)")

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
$chk = Invoke-GdCli -Verb 'check-stages' -Body ([pscustomobject]@{ table = $table; stageText = 'CE-5, LS-5' })
Check '多关卡拆分+去空格' ($chk.Stages.Count -eq 2 -and $chk.Bad.Count -eq 0) $chk.Note
Check '理智合计' ($chk.Cost -eq ([int]$table['CE-5'] + [int]$table['LS-5'])) "$($chk.Cost)"
Check '未知关卡能抓出' ((Invoke-GdCli -Verb 'check-stages' -Body ([pscustomobject]@{ table = $table; stageText = 'XX-9' })).Bad.Count -eq 1)

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

$r1 = Invoke-GdCli -Verb 'apply-maa-daily-config' -Body ([pscustomobject]@{ settings = $S; decision = ($base + @{ Mode = 'idle'; Stage = 'CE-5,LS-5'; ClearSanity = $true }) })
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

$r2 = Invoke-GdCli -Verb 'apply-maa-daily-config' -Body ([pscustomobject]@{ settings = $S; decision = ($base + @{ Mode = 'event-pending'; Stage = 'SR-8'; ClearSanity = $false }) })
Check '不烧理智的形状: 不写 Fight' ('Fight' -notin $r2.ExpectedChains) ($r2.ExpectedChains -join ',')

$r3 = Invoke-GdCli -Verb 'apply-maa-daily-config' -Body ([pscustomobject]@{ settings = $S; decision = ($base + @{ Mode = 'event'; Stage = 'SR-8'; ClearSanity = $true }) })
Check 'event 档: 刷活动关' ('Fight' -in $r3.ExpectedChains -and (@($r3.Changes | Where-Object { $_ -match 'StagePlan = SR-8' }).Count -gt 0))
$r4 = $null
try { Invoke-GdCli -Verb 'apply-maa-daily-config' -Body ([pscustomobject]@{ settings = $S; decision = ($base + @{ Mode = 'idle'; Stage = 'NOT-A-STAGE'; ClearSanity = $true }) }) | Out-Null } catch { $r4 = $_.Exception.Message }
Check '坏关卡代号会被拦住' ($r4 -and $r4 -match 'NOT-A-STAGE')

Write-Host "`n[t5] 方舟判定链路(会联网拉一次活动接口)"
# ---- 刀⑯ 收官批 笔(b)(2026-11-06)：Get-ArkEvent 出仓，取数半段改问核(换答方不换问法) ----
# 组合式＝Get-GdNowMs(现场时钟留壳§9-2) + read-ark-activity(三档与两句 WARN 原话全在核，Round.Data.cs::ArkActivity)
# + Lines 逐条回放 + Resolve-ArkPlan(转发壳·领空折算臂留壳，k371 mutation 证有牙)。
function Get-ArkEventViaKernel {
    param($S, [switch]$Offline)
    $now = Get-GdNowMs
    $d0 = Invoke-GdCli -Verb 'read-ark-activity' -Body ([pscustomobject]@{
        settings = [pscustomobject]@{ ark = $S.ark }; paths = $S.paths; offline = [bool]$Offline })
    foreach ($l in @($d0.Lines)) { if ($l) { Write-GdLog ([string]$l) -Level WARN } }
    return (Resolve-ArkPlan -S $S -Data $d0.Data -Source $d0.Source -Now $now)
}
$a = Get-ArkEventViaKernel -S $S
Check '返回模式合法' (@('idle', 'event', 'event-pending') -contains $a.Mode) "mode=$($a.Mode) stage=$($a.Stage)"
Check '有理智计划' ($a.Stage -and (Invoke-GdCli -Verb 'check-stages' -Body ([pscustomobject]@{ table = $table; stageText = ([string]$a.Stage) })).Bad.Count -eq 0) (Invoke-GdCli -Verb 'check-stages' -Body ([pscustomobject]@{ table = $table; stageText = ([string]$a.Stage) })).Note
# 这条判据在 2026-10-12 第 1 刀**反了向**：旧口径是"没确认就整轮不烧理智"，
# 新口径是"今天自证进不去 → 当日改刷长草套餐，理智照烧"(用户原话「活动要打…没打通就别空烧」)。
Check 'event-pending 当日仍烧理智(改刷长草，不空放)' (-not ($a.Mode -eq 'event-pending' -and -not $a.ClearSanity)) "mode=$($a.Mode) clear=$($a.ClearSanity)"
$b = Get-ArkEventViaKernel -S $S -Offline
Check '离线可降级' (@('idle', 'event', 'event-pending') -contains $b.Mode) "source=$($b.Source)"

Write-Host "`n[t7] 活动门(每轮自证)+商店领空 gate(假数据 + 临时 state，跑完还原)"
# ark-event-ack 那本账不再参与方舟判定(10-12 第 1 刀)，这里就不快照它了；快照 ark-event-probe 是因为探针档会写盘。
Save-GdTestState -Names @('ark-event-probe', 'ark-shop-done')
function Set-FakeArkProbe {
    <# 第 1 刀(2026-10-12)的夹具：往 state\ark-event-probe.json 写一条"活动图自证结论"。
       正常路径上这文件只由核内 daily_round_chain 的自证段写(verb update-ark-event-probe；lib\ark-module.ps1 的 Run 钩子已随 11-04 刀⑤ 出仓)。自检不许起进程、
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
    Invoke-GdCli -Verb 'set-ark-shop-state' -Body ([pscustomobject]@{ eventKey = 'zztest-event'; eventTip = '测试'; done = $true }) | Out-Null
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
    Invoke-GdCli -Verb 'set-ark-shop-state' -Body ([pscustomobject]@{ eventKey = 'zztest-event2'; eventTip = '测试A'; done = $true }) | Out-Null
    $q4 = Resolve-ArkPlan -S $S -Data $two -Source '假数据' -Now $nowMs
    Check '都领空 → 长草计划' ($q4.Mode -eq 'idle' -and $q4.ShopDone) $q4.Reason
$rvReset = Invoke-GdCli -Verb 'set-ark-shop-state' -Body ([pscustomobject]@{ eventKey = 'zztest-event'; done = $false })
$dsAfter = Invoke-GdCli -Verb 'read-decision-state' -Body ([pscustomobject]@{ game = 'ark'; want = @('shopDone') })
Check '撤销标记生效(Action=reset 且表里已无此键——ContainsKey 那把不分大小写的尺在核侧同一把)' (
    $rvReset.Action -eq 'reset' -and -not $dsAfter.ShopDone.PSObject.Properties['zztest-event']) "action=$($rvReset.Action)"
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
# 11-04 转接刀·运行面刀⑦ 笔(c/d) 作废登记①：这里原本 dot 一份 lib\ark-daily.ps1(编排岛)。那件整件出仓，
# 这条 dot 随它一起没了——不是"删掉一行留个注释"，是它点的那件在仓里从此不存在，留着当场抛红。
# 上面那句"重复 dot 只是重新定义同名函数，无副作用"自此按历史引文读：它说的那件在仓外。
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
$arkRoundPs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\rust-round.ps1') -Raw -Encoding utf8
$arkRoundCode = ($arkRoundPs -replace '(?s)<\#.*?\#>', ' ') -replace '(?m)^\s*#.*$', ' '
$arkCoreRs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rustcore\src\main.rs') -Raw -Encoding utf8
$arkVisionCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Vision.SelfTest.cs') -Raw -Encoding utf8
Check 'arkdrive 门两档的行为判据已在核内 --selftest 第 29 节(门退役后尺住在代码里)' (
    ($arkCoreRs.Contains('第 29 节：arkdrive 门退役四组真空档补尺')) -and ($arkCoreRs.Contains('C-retry-relaunch')) -and
    ($arkCoreRs.Contains('C-desk-empty-vs-early')))
# 11-04 转接刀·运行面刀⑦ 笔(c/d) 作废登记②：这里原本有三格(ark executor 的 ask 白名单十一枚／run·mark·obsrec·admin
# 四枚 case 不许复活／信封 role 字面 R3-drive-ark-daily 仍在)，量的是编排岛 lib\ark-daily.ps1 里那台**驱动档**
# executor 的源码形状。岛整件出仓后 PS 侧没有那台 executor，三格当场没有桌子，逐枚写下它们不再量什么、不静默删：
#   · 十一枚那本是驱动档的数。轮档件现拍的 case 名册刀⑧(2026-11-04) 那帧是三枚、刀⑩(2026-11-05) 起是一枚
#     (只剩 round-elevate；round-supervisor-start／-stop 随臂出册，再往前刀⑦ 那帧是五枚、updgate／audit 两枚出册)，
#     而两件头注本来就明写「不要把驱动档那十四枚白名单当这枚名册用，
#     那是另一族的数」——不同族的两本名册从不通约，所以这三格**搬不了靶**：硬搬等于把轮档那本当驱动档那本用。
#   · run／mark 那几枚动作的真身在核内(--selftest 第 29 节那批钉着)，家一字未动；变的只是"PS 侧不再有人
#     对着它们写 switch"。
#   · 信封 role 字面随 executor 一起出仓；驱动档那本信封自此没有 PS 侧的写信人，核内 --drive-ark-daily 成
#     死出口候选(§11.235 已登记，账记在"名册枚数"那侧、不记在净行数)。
# 上面那句「今天读的两份——lib\ark-daily.ps1 与 tools\rustcore\src\main.rs」自本批改按历史引文读：今日读的
# 两份是 lib\rust-round.ps1 与 tools\rustcore\src\main.rs，"三棵树都在场⇒合回无条件一档"那条判据一字未动。
# ctx 的**写侧**半边(原门 :825 那句「逐枚点名取键那条硬约束就在这里验收」)：读侧取值由 --selftest 第 20 节钉，
# 这里钉的是**装配 ctx 的那一侧**往 ctx 里塞了什么——runtime 那批键必须逐枚点名取，而整块 $S.runtime 里住着
# 视觉兜底的 API key，所以那一侧全文不许把整块序列化进账。判据没动，家从编排岛换成轮档件(搬靶)；末那枚的
# 等号右值按对面现量代改：旧壳里那枚累加器叫 $benignMaa，轮档件里叫 $benign——取的是"逐枚点名后累加"这个形。
# ⚠ 收紧一格(mutation m1 现场教出来的)：原先写成 .Contains('[int]$S.runtime.stallTimeoutMinutes') 是**前缀锚**——
# 对面把右值改成 stallTimeoutMinutesXX 照样命中；m1 实跑交回 207/0 假绿(现拍在 ship-1026\raw\k813 那本 log)，
# 这格对"取错键名"当场没牙。自此两重收窄：
#   · 整行钉：载荷里的键名与右值 $S.runtime.<同名键>必须逐枚**相等**且行尾就到，多一个字符即红——
#     "左右同名"这一半本来就是"逐枚点名"的语义，前缀锚把它量成了"出现过这段字面"；
#   · 按函数体钉：轮档件里 stallTimeoutMinutes 与 visionMaxRescue 在两枚载荷(maaRun／m9aRun)里各出现一次，
#     全文钉会让 m9aRun 那枚替 maaRun 顶包(同一行形状两枚都有)，所以靶缩进 Get-GdRoundMaaRunPayload 本体。
# 收窄后同一发 m1 复拍：206/1，FAIL 当场点名 stallTimeoutMinutes(k814 那本 log)——这格自此有牙。
# ⚠ 改口(11-06 转接刀·运行面刀⑪ 笔(c))：上面两段自此按历史引文读——ctx 的装配整块搬进了核对面
# tools\panel-cs\Round.Host.cs(MaaRun／M9aRun 两枚载荷)，lib\rust-round.ps1 里那三枚真身当场没有对面了。
# 换的只是语法，判据一个字没动：整行钉(行尾就到，多一个字符即红)、左右同名、按函数体切(全文钉会让
# m9aRun 那枚替 maaRun 顶包)三形照旧——那条 m1 教训在前缀锚上成立的道理跟引擎无关。
# 旧 PS 侧那格不静默消失：换成下面那枚「退役不回潮」负锚，防的是有人把装配定义搬回 PS 侧造出双账。
$arkHostCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Round.Host.cs') -Raw -Encoding utf8
$arkHostCode = ($arkHostCs -replace '(?s)/\*.*?\*/', ' ') -replace '(?m)^\s*//.*$', ' '
$arkMaaRunBody = [regex]::Match($arkHostCs, '(?s)static Dictionary<string, object> MaaRun\(.*?\r?\n        \}').Value
$arkCtxBad = @()
foreach ($arkCtxKey in @('arkStartTimeoutMinutes', 'arkTimeoutMinutes', 'stallTimeoutMinutes', 'idleConfirmSeconds', 'abortOnMaaStallWarning', 'visionMaxRescue')) {
    if ($arkMaaRunBody -notmatch ('(?m)^\s*"' + $arkCtxKey + '",\s*Ps(Int|Bool)\(Gd\.Get\(runtime, "' + $arkCtxKey + '"\)\),\s*$')) { $arkCtxBad += $arkCtxKey }
}
Check 'ctx 的 maaRun 载荷逐枚点名取键且左右同名(按函数体整行钉；不整块序列化 runtime；11-06 笔(c) 搬靶到直身件 Round.Host.cs)' (
    ($arkCtxBad.Count -eq 0) -and ($arkMaaRunBody -match '(?m)^\s*"benignMaaErrors",\s*benign\)\);\s*$') -and
    ($arkMaaRunBody -match '(?m)^\s*foreach \(object bm in Gd\.List\(Gd\.Get\(runtime, "benignMaaErrors"\)\)\)\s*benign\.Add')) ($arkCtxBad -join ',')
# 负锚那副眼镜跟着搬家：直身件里 visionApiKey 的命中现拍全在注释里(讲"整块 runtime 里住着 key"那处)，
# 所以代码面负扫＋原文在场自证两半都要——判据不许动的是「不许出现的是代码面」这句。
Check '直身件的代码面一个字都不碰视觉 API key(visionApiKey 不许进 ctx 那本留盘的账；负锚按剥注释后抓)' (
    (-not $arkHostCode.Contains('visionApiKey')) -and ($arkHostCs.Contains('visionApiKey')))
# 「退役不回潮」那枚(形状照下面编排岛名册那一格；名册由 foreach 供数，注释不写枚数)：PS 侧自此只递旋钮、
# 不再自己装配 ctx——装配的唯一出口是 verb build-round-ctx，且这侧调用点只此一处(两处＝双账)。
$arkCtxDefBad = @()
foreach ($arkCtxFn in @('Get-GdRoundCtx', 'Get-GdRoundMaaRunPayload', 'Get-GdRoundM9aRunPayload')) {
    if ($arkRoundCode.Contains('function ' + $arkCtxFn + ' {')) { $arkCtxDefBad += $arkCtxFn }
}
$arkCtxVerbHits = [regex]::Matches($arkRoundCode, "Invoke-GdCli -Verb 'build-round-ctx'").Count
Check '轮档件的 PS 侧不再自己装配 ctx(三枚定义不许回潮；装配只走 build-round-ctx 那一枚出口且调用点唯一)' (
    ($arkCtxDefBad.Count -eq 0) -and ($arkCtxVerbHits -eq 1)) (((($arkCtxDefBad -join ',') + '|verb-hits=' + $arkCtxVerbHits)))
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
# 2026-11-06 刀⑮ 笔(a)：这枚读改成不依赖件在场——件在按老形咬件文本(负锚原样有牙)；件不在改成咬
# "六枚没以命令形态在别处复活"(Get-Command 现读)。两臂都交得出数，缺读数不许长成活锚。
$visionRescuePsPath = Join-Path $PSScriptRoot '..\lib\vision-rescue.ps1'
$visionRescuePsOnDisk = Test-Path -LiteralPath $visionRescuePsPath
$visionRescuePs = if ($visionRescuePsOnDisk) { Get-Content -LiteralPath $visionRescuePsPath -Raw -Encoding utf8 } else { '' }
if ($visionRescuePsOnDisk) {
    $vrSixTooth = (-not $visionRescuePs.Contains('function Invoke-GdVisionRescue ')) -and
        (-not $visionRescuePs.Contains('function New-GdRescueSkip ')) -and
        (-not $visionRescuePs.Contains('function Clear-GdRescueShotDir ')) -and
        (-not $visionRescuePs.Contains('function Get-GdRescueLedgerPath ')) -and
        (-not $visionRescuePs.Contains('function Test-GdShotChanged ')) -and
        (-not $visionRescuePs.Contains('function Add-GdRescueRecord '))
    $vrSixWhy = ''
} else {
    $vrRevived = @()
    foreach ($vrFnName in @('Invoke-GdVisionRescue', 'New-GdRescueSkip', 'Clear-GdRescueShotDir', 'Get-GdRescueLedgerPath', 'Test-GdShotChanged', 'Add-GdRescueRecord')) {
        if (Get-Command $vrFnName -ErrorAction SilentlyContinue) { $vrRevived += $vrFnName }
    }
    $vrSixTooth = (@($vrRevived).Count -eq 0)
    # ⚠ 11-06 刀⑮ 笔(a) 验证自伤更正：原来这里挂一枚 $script:_vrSixWhy 且只在复活>0 时才赋值，
    #   件不在又没复活时 detail 的 elseif 读一枚从没设过的脚本变量——strict mode 当场抛"无法检索变量"，
    #   等于把「双绿臂」里最该安静的那条走成炸门。改本地变量＋两臂都先初始化，缺读数不许长成活锚也不许长成一枚雷。
    $vrSixWhy = $(if (@($vrRevived).Count -gt 0) { '件已不在，但这几枚以命令形态复活：' + ($vrRevived -join ',') } else { '' })
}
Check '兜底编排六枚的定义不在现树 PS 侧(双删是回归抓器：编排只住核内 vision_rescue 一处；件在咬文本、件不在咬命令复活)' $vrSixTooth $(
    if ($visionRescuePsOnDisk) { "件在场 $($visionRescuePs.Length) 字符" } elseif ($vrSixWhy) { $vrSixWhy } else { '件不在，六枚命令名册现读为空' })
Check '刀③ 补尺两枚住在核内第 19 节(链不记帐 / context 原样递到问价层)' (
    ($arkCoreRs.Contains('第二十刀刀③ 补尺①')) -and ($arkCoreRs.Contains('第二十刀刀③ 补尺②')))
Check '画面变没变的四形与 detail 压平两形住在 C# 自检里(Vision.SelfTest.cs 接守 t13/t16 摘下的那两族)' (
    ($arkVisionCs.Contains('只有一格抖 1 档')) -and ($arkVisionCs.Contains('两次画面格数不同')) -and
    ($arkVisionCs.Contains('detail 换行压平')))

# ── 转接刀·方舟拉起族(11-03)补尺格：三处消费面各自现问两枚核内出口 ──────────────
# 为什么钉"现问的形状"而不是钉结果：这一族的语义闸是**取回执里哪一枚键**——start-ark-client 的
# Done 恒真(路径闸过了就叫做完)，Started 才是"真进到了游戏"；取错就放回 10-11 那次对着更新页
# 把五个任务全跑错(14m23s)的缺陷。核内自检(Round.SelfTest 第 21/25 节)钉的是核怎么答，钉不到
# PS 这一侧怎么取 ⇒ 这一格只能由本套件钉源码形状(与本文件 ②-d 刀① 那批 .Contains() 同形)。
# Body 那半是安全边界：两枚都传空块，核自己现场读 config\settings.json(与 $S 同源)；整块序列化
# $S 会把 visionApiKey／webhook 那类本机专属值落进临时 JSON——那是"抄配置"不是"读配置"。
$arkModulePs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\ark-module.ps1') -Raw -Encoding utf8
# 11-04 转接刀·运行面刀⑦ 笔(c/d) 作废登记③：上面那三格拉链(拉起答臂现问 start-ark-client 且只认 Started／
# 链体答臂现问 stop-maa-and-game／链体回放核内话术 Lines 现量 2 发)钉的全是编排岛里那台 executor **怎么取回执**。
# 这一族的家本来就在那句话上：核内自检(Round.SelfTest 第 21/25 节)钉的是核怎么答，钉不到 PS 这一侧怎么取 ⇒
# 只能由本套件钉源码形状。PS 侧不再有人取 ⇒ 三格当场没有桌子；语义一个字没丢，它在核内与 C# 那两处都有真身：
#   · "取 Started 不取 Done" —— 家 tools\panel-cs\Chain.cs 的 StartArkClient 答形＋Round.SelfTest 第 25 节；
#   · "问 stop-maa-and-game" —— 家 Chain.cs 的 StopMaaAndGame＋第 21 节；核内收尾那一路(main.rs 的 stop:ark)
#     现问它，PS 侧自此不是那一路的写信人；
#   · "Lines 回放一句不丢" —— 家 Chain.cs 那枚回执的 Lines 名册与核内 DirectOut::with_lines。
# ⚠ 这三格**不搬靶**给轮档件：轮档件的代码面现拍一条 Invoke-GdCli -Verb 'start-ark-client'／'stop-maa-and-game'
# 都没有(刀⑧ 起它现问的只剩监督两枚那族 verb，updgate／audit 两臂已随核内直答出册)，
# 把"PS 侧只此一处"的负锚改成"两处都数"是给不存在的桌子补椅子。
# 同一批留一枚「退役不回潮」负锚，形状照下面那格拉起族三枚真身那形：岛上那批真身(枚数由下面 foreach 的名册供数，注释不写数——写死的枚数会被下一次扩名册变成陈旧账)若被人搬回 PS 侧，
# 最可能落的两件就是轮档件与清单件——这一格不防功能缺失(功能由核内自检钉)，防的是那本双账复活。
$arkIslandBad = @()
foreach ($arkIslandFn in @('Set-GdArkShopState', 'Resolve-GdArkDecision', 'Show-GdArkPreview', 'Start-GdArkDaily', 'Get-GdArkDriveExe', 'Invoke-GdArkDailyRust')) {
    if ($arkRoundPs.Contains('function ' + $arkIslandFn + ' ') -or $arkModulePs.Contains('function ' + $arkIslandFn + ' ')) { $arkIslandBad += $arkIslandFn }
}
Check '编排岛真身的定义不在轮档件与清单件里(名册逐枚现扫；回潮＝核内一份＋PS 一份那本双账复活；运行面唯一一条腿是 daily-clear→rust-round→--daily-round)' ($arkIslandBad.Count -eq 0) ($arkIslandBad -join ',')
# 同一批的「退役不回潮」负锚（形状照上面刀③ 那格）：lib\maa.ps1 那三枚真身（Wait-GdArkLauncherReady／
# Start-GdArkClient／Stop-MaaAndGame）整件出仓后，这一路的唯一事实源在 tools\panel-cs\Chain.cs。
# 这一格不防功能缺失（功能由核内自检钉），防的是"有人把定义搬回 PS 侧"——那会让核内一份＋PS 一份那本双账复活。
$arkMaaPs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\maa.ps1') -Raw -Encoding utf8
Check '拉起族三枚真身的定义不在现树 PS 侧(双删是回归抓器：起进程／启动器页／进程树收尾只住核内 Chain.cs 一处)' (
    (-not $arkMaaPs.Contains('function Wait-GdArkLauncherReady ')) -and
    (-not $arkMaaPs.Contains('function Start-GdArkClient ')) -and
    (-not $arkMaaPs.Contains('function Stop-MaaAndGame ')))
# 转接刀·运行面刀⑨ 的「退役不回潮」负锚（形状照上面拉起族那格）：本批出仓的五枚 AST 零调用死真身里，这一路
# 看得见的四枚——lib\common.ps1 的 Invoke-GdTakeover／Get-GdWindowByTitle 与 lib\maa.ps1 的
# Get-GdMaaFightSkip／Get-GdMaaStageObservation——判据本体早在历刀进核(Orchestration.cs 两枚 detect／observe，
# 对面读盘与接管在 Chain.cs)，这一格不防功能缺失，只防"有人把定义搬回 PS 侧"那本双账复活。
# 名册由下面 foreach 供数，注释不写死枚数(在册「枚数两种身份」：帧的历史可写死，树的现量只能供数)。
$arkCommonDeadPs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\common.ps1') -Raw -Encoding utf8
$arkCut9Bad = @()
foreach ($arkCut9Fn in @('Invoke-GdTakeover', 'Get-GdWindowByTitle', 'Get-GdMaaFightSkip', 'Get-GdMaaStageObservation')) {
    if ($arkCommonDeadPs.Contains('function ' + $arkCut9Fn + ' ') -or $arkMaaPs.Contains('function ' + $arkCut9Fn + ' ')) { $arkCut9Bad += $arkCut9Fn }
}
Check '刀⑨ 四枚死真身的定义不在现树 PS 侧(common 与 maa 两件按名册逐枚现扫；回潮＝零调用尺白跑，判据只住核内与 Chain.cs)' ($arkCut9Bad.Count -eq 0) ($arkCut9Bad -join ',')

Write-Host "`n[t12] asst.log 停滞线索(gui.log 静默时唯一看得见的东西)"
# 2026-09-24 18:00 那轮：gui.log 22 分钟一个字没有，asst.log 里 StartUp@GameStart 的 exec_times 从 1 涨到 316。
# 断言用的是当晚日志的真实片段(去掉无关字段)，这样 MAA 改了行格式会立刻在这里红，而不是又在当晚才发现。
$asstExcerpt = @'
[2026-09-24 18:23:26.192][INF][Px29472][Tx36949] {"class":"asst::ProcessTask","cur_task":"StartUp@GameStart","details":{"cur_retry":0,"retry_times":50,"to_be_recognized":["StartUp@GameStart"]},"taskchain":"StartUp","taskid":0}
[2026-09-24 18:23:26.320][INF][Px29472][Tx36949] Assistant::append_callback | SubTaskStart {"class":"asst::ProcessTask","details":{"action":"ClickSelf","algorithm":"MatchTemplate","exec_times":316,"max_times":2147483647,"result":{"rect":[611,652,58,58],"score":0.991275,"template":"GameStart.png"},"task":"GameStart"},"subtask":"ProcessTask","taskchain":"StartUp","taskid":0}
[2026-09-24 18:23:26.320][TRC][Px29472][Tx36949] Win32Controller click: (629, 701)
'@
$asstHint = (Invoke-GdCli -Verb 'parse-asst-hint' -Body ([pscustomobject]@{ text = $asstExcerpt })).Hint
Check '能点名卡住的子任务 + 重复次数 + 最后点击位置' (
    $asstHint -match 'StartUp@GameStart' -and $asstHint -match '316' -and $asstHint -match '629,701') $asstHint
Check '认不出任务时不给线索(不编造)' (((Invoke-GdCli -Verb 'parse-asst-hint' -Body ([pscustomobject]@{ text = '[INF] asst::Controller::connect 123' })).Hint) -eq '')
Check '空文本不炸(对面空文本自证：不起判定进程的那半已随壳出仓，这里量的是 verb 对空白的答法)' (((Invoke-GdCli -Verb 'parse-asst-hint' -Body ([pscustomobject]@{ text = '' })).Hint) -eq '')
# 只点了一两次 = 正常推进，不该跟着喊"被挡住了"(那条结论只在反复点同一处时才成立)
$justOne = (Invoke-GdCli -Verb 'parse-asst-hint' -Body ([pscustomobject]@{ text = (@'
{"cur_task":"RecruitBegin","details":{"cur_retry":0,"retry_times":50}}
SubTaskStart {"details":{"exec_times":1,"task":"RecruitBegin"}}
Win32Controller click: (400, 300)
'@) })).Hint
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
    Write-Host "  本机 asst.log 末尾现况：$((Invoke-GdCli -Verb 'parse-asst-hint' -Body ([pscustomobject]@{ text = ((Get-Content -LiteralPath $liveAsst -Tail 800 -Encoding utf8) -join "`n") })).Hint)" -ForegroundColor DarkGray
}

Write-Host "`n[t13] 视觉兜底(全程不联网、不截图、不点任何东西)"
# 2026-11-06 刀⑮ 笔(d)：本节原有那二十二枚行为级格真调 lib\vision-rescue.ps1 与 lib\vision-ark.ps1 腹内的六枚函数
# (抠回件、拼提示词、归一端点、千分比换算、截图带回签名、问价)。三件本体随本批出仓，这二十二枚的家由覆盖面尺
# raw\k17a-cut15d-vision-coverage.txt 逐格对平到 C# 那侧(HIT 十六／WEAK 十五逐格另查／MISS 十四里 vision 那六枚
# 另查——MISS 是"名字最长公共子串不够长"，不是"没有对面"：L453 的对面的确在 Vision.SelfTest.cs:146，只是它把
# "模型按格式回"写成了"按格式回"，L468 与 :157 逐字同名)，逐档判语进本帧 docs。留下的换成无条件格，三条在册规矩：
#   ① 对面不是"钩子格还在"而是**同一条判据在 --visiontest／--livetest 里被重跑一遍** ⇒ 按刀③ 那句"把真调换成
#      钩子格还在的形钉等于给壳续命"直接删格，不换取法重写；
#   ② 删格不等于删判据：件在不在都跑的那四枚是承接，只在件不在时跑的负锚挡半迁移(同事实格在上面)；
#   ③ .cs 文本取不回来一律当场红并交出字节数(交空串＝尺没接电)，静默跳过正是要防的"绿着但没人检查"。
$rescueOnDisk = Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\lib\vision-rescue.ps1')
Check '兜底内核件与 Get-GdVisionVerdictFromText 命令同一个事实(同在同不在，半迁移红)' (
    $rescueOnDisk -eq [bool](Get-Command Get-GdVisionVerdictFromText -ErrorAction SilentlyContinue)) "件=$rescueOnDisk"
$visionCsT13 = ''
try { $visionCsT13 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Vision.cs') -Raw -Encoding utf8 } catch { }
Check '提示词那一份规则住在核侧(只回 JSON＋千分比＋clicks 最多 3 个按把握排＋只允许关掉弹窗那类＋默认档硬禁领取)' (
    $visionCsT13.Length -gt 0 -and $visionCsT13.Contains('只输出一个 JSON') -and $visionCsT13.Contains('千分比') -and
    $visionCsT13.Contains('clicks 最多 3 个') -and $visionCsT13.Contains('按你的把握从大到小排') -and
    $visionCsT13.Contains('关闭/取消/暂不/跳过/知道了') -and $visionCsT13.Contains('绝对不要给')) ("Vision.cs=" + $visionCsT13.Length + " 字符")
$liveCsT13 = ''
try { $liveCsT13 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Live.cs') -Raw -Encoding utf8 } catch { }
Check '端游截图与点击那半的规矩住在核侧(带回 Sig、最小化先 SW_RESTORE、抢不到前台才退 PostMessage)' (
    $liveCsT13.Length -gt 0 -and $liveCsT13.Contains('"Sig"') -and $liveCsT13.Contains('IsIconic') -and
    $liveCsT13.Contains('SW_RESTORE') -and $liveCsT13.Contains('TryForeground') -and
    $liveCsT13.Contains('RealClick') -and $liveCsT13.Contains('ClickOnce')) ("Live.cs=" + $liveCsT13.Length + " 字符")
# 刀⑰ 笔(c)-2 第 1 批 B1 换家(§11.276)：老形是 PS 侧 Get-Content -Raw 读整本 Cli.cs，再逐枚手拼
# 'verb == "<名>"' 拿去 -notmatch —— 那两步(读文件＋正则判定)的家自此住核内 scan-source-patterns，
# PS 侧只组参与按 Passed 记名。两处语义差逐格登记：
#   ① PS -match 原生大小写不敏感、核侧敏感(RegexOptions.CultureInvariant)。分派链那行是 C# 字面量，
#     老形会把「Verb == "x"」这种对不齐大小写的写法也算在位；改敏感后是收紧不是放松，现树逐枚现读全在位。
#   ② 老形「Cli.cs 取不回来 ⇒ 空串 ⇒ 十三枚全红」是静默恒红；核侧输入闸对缺文件直接 throw(拒跑不是判红)，
#     交不出数的两档从此分家——正是上面③那条在册规矩要的形。
$t13CliCs = Join-Path $PSScriptRoot 'panel-cs\Cli.cs'
$t13Verbs = @('vision-ask-model', 'parse-vision-verdict', 'build-vision-prompt', 'resolve-vision-endpoint',
    'vision-click-point', 'shot-changed', 'ark-window-shot', 'ark-window-click', 'ark-desktop-state',
    'compose-ark-desktop-state', 'resolve-rescue-context', 'mumu-screen-shot', 'mumu-screen-click')
$t13Miss = @()
foreach ($t13v in $t13Verbs) {
    $t13Scan = Invoke-GdCli -Verb 'scan-source-patterns' -Body ([pscustomobject]@{
        files = @($t13CliCs); pattern = 'verb == "' + [regex]::Escape($t13v) + '"'; expect = 'nonzero' })
    if (-not [bool]$t13Scan.Passed) { $t13Miss += $t13v }
}
Check '兜底那一路的十三枚出口全在核内分派链上(三件出仓后这是唯一通路，缺哪枚点名哪枚)' ($t13Miss.Count -eq 0) ($t13Miss -join ',')
$visionStT13 = ''
try { $visionStT13 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Vision.SelfTest.cs') -Raw -Encoding utf8 } catch { }
Check '那二十二枚的判语在 --visiontest 里逐族重跑(抠件／点位上限／越界拒／端点补全／桌面态／画面签名六族同名在场)' (
    $visionStT13.Length -gt 0 -and $visionStT13.Contains('裹了 markdown 代码块和一句话也能抠出 JSON') -and
    $visionStT13.Contains('Clicks 只留整数点位、最多 3 个') -and
    $visionStT13.Contains('坐标超出 0-1000 视为胡说，拒掉') -and
    $visionStT13.Contains('基础地址以 /v1 结尾会补成 /chat/completions') -and
    $visionStT13.Contains('桌面名读不到') -and $visionStT13.Contains('两次画面格数不同')) ("Vision.SelfTest.cs=" + $visionStT13.Length + " 字符")
if (-not $rescueOnDisk) {
    Check 'PS 侧那六枚兜底真身没在现树复活(问价／解析／提示词／端点／换算／截图签名)' (
        -not (Get-Command Get-GdVisionVerdictFromText -ErrorAction SilentlyContinue) -and
        -not (Get-Command Get-GdVisionSystemPrompt -ErrorAction SilentlyContinue) -and
        -not (Get-Command Resolve-GdVisionEndpoint -ErrorAction SilentlyContinue) -and
        -not (Get-Command Get-GdRescueClickPoint -ErrorAction SilentlyContinue) -and
        -not (Get-Command Invoke-GdVisionRaw -ErrorAction SilentlyContinue) -and
        -not (Get-Command Save-GdWindowShot -ErrorAction SilentlyContinue))
    $liveStT13 = ''
    try { $liveStT13 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Live.SelfTest.cs') -Raw -Encoding utf8 } catch { }
    Check '问价那一层"拼处境＋截 200 字"两条住在核侧(截断在 Live.cs，逐字金样在 --livetest 那两格)' (
        $liveCsT13.Contains('自动化这边的处境') -and $liveCsT13.Contains('Substring(0, 200)') -and
        $liveStT13.Contains('自动化这边的处境') -and $liveStT13.Length -gt 0) ("Live.SelfTest.cs=" + $liveStT13.Length + " 字符")
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
$stDead = Invoke-GdCli -Verb 'parse-asst-state' -Body ([pscustomobject]@{ text = $asstDead })
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
$stSwipe = Invoke-GdCli -Verb 'parse-asst-state' -Body ([pscustomobject]@{ text = $asstSwipe })
Check '注入行只在滑动类子任务里出现，数得到就不等于"点击通道活着"' (
    $stSwipe.Task -eq 'InfrastTimePhase' -and $stSwipe.Inject -eq 2 -and $stSwipe.Clicks -eq 0) $(
    "task=$($stSwipe.Task) inject=$($stSwipe.Inject) clicks=$($stSwipe.Clicks)")
$hintDead = (Invoke-GdCli -Verb 'parse-asst-hint' -Body ([pscustomobject]@{ text = $asstDead })).Hint
Check '点了没动时两种可能都留着，不再把某个原因写成定论' (
    $hintDead -match '窗口挡' -and $hintDead -match '前台|会话') $hintDead
Check '结论里不出现"通道退化/不吃 PostMessage"那句(它已被证伪)' (
    $hintDead -notmatch '通道退化' -and $hintDead -notmatch '不吃 PostMessage' -and $hintDead -notmatch '八成是') $hintDead
Check '任务名/重试次数/最后点击位置三个字段照常带上' (
    $hintDead -match 'StartUp@GameStart' -and $hintDead -match '269' -and $hintDead -match '638,663')
Check '空片段不给状态、也不给结论' (
    (-not (Invoke-GdCli -Verb 'parse-asst-state' -Body ([pscustomobject]@{ text = '' })).Task) -and (((Invoke-GdCli -Verb 'parse-asst-hint' -Body ([pscustomobject]@{ text = '' })).Hint) -eq ''))
# 探测那一路：桌面态/截图/点击的真身在核内(Live.cs 那三段＋GdWin.cs 那份 P/Invoke 名单)，PS 后端件随本批出仓。
# 2026-11-06 刀⑮ 笔(d)：下面两枚 GdWin.cs 钉**提出护栏**——它们量的是 tools\gdinterop\GdWin.cs 的名单在场，
# 与 lib\vision-ark.ps1 在不在**不同轴**；留在护栏内＝件一摘这两枚跟着断电(在册那条"桌子搬了家而九格靠空串假绿")
# 正是这一形。护栏自此只留"件在才跑得动的真调格"；件不在不许正锚空咬，改咬那三枚没复活＋桌面态金样在 --visiontest 重跑。
$arkVisionFileOnDisk = Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\lib\vision-ark.ps1')
Check '端游视觉后端件与 Get-GdArkDesktopState 命令同一个事实(同在同不在，半迁移红)' (
    $arkVisionFileOnDisk -eq [bool](Get-Command Get-GdArkDesktopState -ErrorAction SilentlyContinue)) "件=$arkVisionFileOnDisk"
$gdWinCs = ''
try { $gdWinCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\tools\gdinterop\GdWin.cs') -Raw -Encoding utf8 } catch { }
$arkVisionTxt = if ($arkVisionFileOnDisk) { Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\vision-ark.ps1') -Raw -Encoding utf8 } else { '' }
Check '桌面名走 OpenInputDesktop + UOI_NAME，用完关掉句柄(名单只在 tools\gdinterop\GdWin.cs 里，也不许内联回 PS 那份)' (
    $gdWinCs.Length -gt 0 -and $gdWinCs -match 'OpenInputDesktop' -and $gdWinCs -match 'GetUserObjectInformationW' -and
    $gdWinCs -match 'CloseDesktop' -and $arkVisionTxt -notmatch 'Add-Type -TypeDefinition') \
    ("GdWin.cs={0} 字符 / vision-ark 仍内联 C#={1}" -f $gdWinCs.Length, ($arkVisionTxt -match "TypeDefinition"))
Check '探测还能说清"谁占着前台"，并且读窗口自身状态(最小化/可见/矩形)' (
    $gdWinCs.Length -gt 0 -and $gdWinCs -match 'GetWindowThreadProcessId' -and $gdWinCs -match 'IsWindowVisible' -and
    $gdWinCs -match 'WindowRectText')
if ($arkVisionFileOnDisk) {
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
    Check '抢前台只动窗口状态，绝不往客户区点一下，并把现场带回 Detail' (
        $fnGrab -match 'TryForeground' -and $fnGrab -notmatch 'RealClick' -and $fnGrab -notmatch 'ClickOnce' -and
        $fnGrab -match 'st\.Detail')
} else {
    Check 'PS 端游后端那三枚没在现树复活(找窗口／拍窗口／点窗口)' (
        -not (Get-Command Get-GdArkWindow -ErrorAction SilentlyContinue) -and
        -not (Get-Command Save-GdWindowShot -ErrorAction SilentlyContinue) -and
        -not (Get-Command Send-GdArkClick -ErrorAction SilentlyContinue))
    $visionStT14 = ''
    try { $visionStT14 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Vision.SelfTest.cs') -Raw -Encoding utf8 } catch { }
    $liveStT14 = ''
    try { $liveStT14 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Live.SelfTest.cs') -Raw -Encoding utf8 } catch { }
    Check '桌面态那四格改由 --visiontest 那族金样接住(读不到→无法判断／未锁屏没窗口有光标／屏保两句都说清／最小化不可见矩形并排)' (
        $visionStT14.Length -gt 0 -and $visionStT14.Contains('桌面名读不到') -and
        $visionStT14.Contains('未锁屏 + 没窗口 + 有光标') -and
        $visionStT14.Contains('屏保/登录桌面 + 前台被人占着') -and
        $visionStT14.Contains('最小化+不可见+矩形三样并排')) ('Vision.SelfTest.cs=' + $visionStT14.Length + ' 字符')
    # 11-06 刀⑮ 笔(d)-2 复跑红一次照登：首拍把 TryForeground 去问 Live.SelfTest.cs(现读 0 处)，而它的真身在
    # Live.cs(现读 2 处)——判语句自己写的是「Live.cs 走 TryForeground」，取件取了另一本＝跨轴。金样话术那句确实
    # 住在 SelfTest(现读 1 处)，所以两串各归各家：话术问 SelfTest、窗口调用问 Live.cs，取证轴两本都印出来。
    Check '抢前台那一条在核侧也只动窗口状态(--livetest 钉"全量注入时一个字都不碰窗口调用"，TryForeground 的真身在 Live.cs)' (
        $liveStT14.Length -gt 0 -and $liveStT14.Contains('全量注入时一个字都不碰窗口调用') -and
        $liveCsT13.Contains('TryForeground')) ('Live.cs=' + $liveCsT13.Length + " 字符 / Live.SelfTest.cs=" + $liveStT14.Length + ' 字符')
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
    # 刀⑳ 笔(a)-2 翻形：老形拿未剥注释的 $askSrc 判两枚 PS 函数名，而那两枚已随刀⑮ 笔(d) 整件出仓，
    # 名字只剩 vision-ask 那两处史注替它说话＝覆盖已丢而格仍绿（判死代码时注释不算引用，反过来拿注释当正锚同样是伤）。
    # 新形只认剥注释的代码面：正锚改指真在场的两枚 verb 与话术递到手上的那两格，另加三枚负锚＝
    # 外壳不许复活那两枚 PS 函数，也不许把 scene 写成本地字面量（那才是「另写一份提示词」的真形）。
    Check '复用同一套靶子与同一个问价出口(话术由核供给一次，不另写一份提示词，免得两边规则漂移)' (
        $askCode -match 'resolve-rescue-context' -and $askCode -match 'vision-ask-model' -and
        $askCode -match '\[string\]\$ctx\.Scene' -and $askCode -match '\[string\]\$ctx\.UserText' -and
        $askCode -notmatch 'Get-GdVisionTarget' -and $askCode -notmatch 'Invoke-GdVisionRaw' -and
        $askCode -notmatch "scene\s*=\s*'")
    Check '跑完当面告诉人"本文件没有点任何东西"' ($askSrc -match '没有点任何东西')
    Check '问哪一路由清单的 VisionKind 决定，这份文件里没有 ark/mumu 硬对照表' (
        $askSrc -match 'VisionKind' -and $askSrc -notmatch "=\s*'mumu'")
    Check '给了 -Image 就直接用那张图(不截图，也不会因为后端不在就放弃)' ($askSrc -match '\$Image')
    # 2026-11-06 刀⑮ 笔(c)：这一格的老形咬的是 $t.Enabled / $t.AdminWhy / $t.Alive —— 那是薄壳自己拿靶子对象、
    # 自己判"对象还在不在"的年代。现在三道闸的判语全在核内 resolve-rescue-context 腹内(闸序 hasBuilder→enabled→
    # isAdmin→hasKey→python→alive)，薄壳只转达：Enabled / NeedsAdmin+AdminWhy / CanAsk(+Skip)。所以正锚换成新形，
    # 并补一枚负锚——薄壳不许再自己拼 Alive(搬家非增删；话术与判语只由核供一次，alive 那格由 --livetest 盯)。
    Check '开关关着/没提权/对象不在时只说人话，不硬拍(三闸现由 ctx 转达，判语在核内)' (
        $askSrc -match 'ctx\.Enabled' -and $askSrc -match 'AdminWhy' -and $askSrc -match 'ctx\.CanAsk' -and
        $askCode -notmatch 't\.Alive')
} else {
    Check 'tools\vision-ask.ps1 存在(只问不点的诊断入口)' $false '没找到这份文件'
}

$res = Show-GdTestResult -Tag 'ark'
if ($NoExit) { return $res }
exit $(if ($res.Fail) { 1 } else { 0 })
