# tools/test-ark.ps1 — 明日方舟那一路的纯逻辑自检(只读：不改配置、不启动任何程序)
# 用法: pwsh -NoProfile -File tools\test-ark.ps1        (powershell.exe 5.1 同样能跑)
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
Check '未确认活动: 不烧理智' ('Fight' -notin $r2.ExpectedChains) ($r2.ExpectedChains -join ',')

$r3 = Set-MaaDailyConfig -S $S -Decision ($base + @{ Mode = 'event'; Stage = 'SR-8'; ClearSanity = $true })
Check '已确认活动: 刷活动关' ('Fight' -in $r3.ExpectedChains -and (@($r3.Changes | Where-Object { $_ -match 'StagePlan = SR-8' }).Count -gt 0))
$r4 = $null
try { Set-MaaDailyConfig -S $S -Decision ($base + @{ Mode = 'idle'; Stage = 'NOT-A-STAGE'; ClearSanity = $true }) | Out-Null } catch { $r4 = $_.Exception.Message }
Check '坏关卡代号会被拦住' ($r4 -and $r4 -match 'NOT-A-STAGE')

Write-Host "`n[t5] 方舟判定链路(会联网拉一次活动接口)"
$a = Get-ArkEvent -S $S
Check '返回模式合法' (@('idle', 'event', 'event-pending') -contains $a.Mode) "mode=$($a.Mode) stage=$($a.Stage)"
Check '有理智计划' ($a.Stage -and (Test-GdStages -S $S -StageText ([string]$a.Stage)).Bad.Count -eq 0) (Test-GdStages -S $S -StageText ([string]$a.Stage)).Note
Check 'event-pending 必然不烧理智' (-not ($a.Mode -eq 'event-pending' -and $a.ClearSanity))
$b = Get-ArkEvent -S $S -Offline
Check '离线可降级' (@('idle', 'event', 'event-pending') -contains $b.Mode) "source=$($b.Source)"

Write-Host "`n[t7] 活动商店领空 gate(假数据 + 临时 state，跑完还原)"
Save-GdTestState -Names @('ark-event-ack', 'ark-shop-done')
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
    $p1 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '假活动未确认 → 不烧理智' ($p1.Mode -eq 'event-pending' -and -not $p1.ClearSanity) "stage=$($p1.Stage)"
    Check '未确认时活动关卡只是提示' ($p1.StageHint -eq 'AI-8') $p1.StageHint
    # 提示语是给用户照抄的：单游戏入口只有 -Ack / -ShopReset，写死 -AckArk 会让人敲一个不存在的参数
    Check '未确认的提示语用短参数名 -Ack(不是 -AckArk)' (($p1.Reason -match 'daily-clear\.ps1 -Ack(?!Ark)') -and ($p1.Reason -notmatch 'AckArk')) $p1.Reason
    Set-GdEntryVerb -Game ark -Verb Ack -Name '-AckArk'
    try {
        $p1b = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
        Check '入口覆盖参数名后提示语跟着改(合体工程就是这么跑的)' ($p1b.Reason -match 'daily-clear\.ps1 -AckArk') $p1b.Reason
    } finally { Set-GdEntryVerb -Game ark -Verb Ack -Name '-Ack' }
    Set-GdAckKey -Game 'ark' -Key 'zztest-event'
    $p2 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '确认后 → 刷活动代币关' ($p2.Mode -eq 'event' -and $p2.Stage -eq 'AI-8' -and $p2.ClearSanity) $p2.Reason
    Set-GdShopDoneKey -Game 'ark' -Key 'zztest-event'
    $p3 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '商店领空 → 回落长草计划' ($p3.Mode -eq 'idle' -and $p3.Stage -eq $idleStage -and $p3.ClearSanity -and $p3.ShopDone) $p3.Reason
    $p4 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs -IgnoreShopDone
    Check 'IgnoreShopDone 可回看原结论' ($p4.Mode -eq 'event' -and $p4.EventKey -eq 'zztest-event')
    Check '领空后仍能报出活动 id(供撤销)' ($p3.EventKey -eq 'zztest-event') $p3.EventKey
    Check '领空回落的提示语用短参数名 -ShopReset' (($p3.Reason -match 'daily-clear\.ps1 -ShopReset(?!\w)') -and ($p3.Reason -notmatch 'ArkShop')) $p3.Reason
    $S.ark | Add-Member -NotePropertyName shopDoneStopsEvent -NotePropertyValue $false -Force
    $p5 = Resolve-ArkPlan -S $S -Data $fake -Source '假数据' -Now $nowMs
    Check '开关置 false 后不再拦截' ($p5.Mode -eq 'event')
    $S.ark | Add-Member -NotePropertyName shopDoneStopsEvent -NotePropertyValue $true -Force
    $q1 = Resolve-ArkPlan -S $S -Data $two -Source '假数据' -Now $nowMs
    Check 'A 已领空 → 转到未确认的 B 并提醒' ($q1.Mode -eq 'event-pending' -and $q1.EventKey -eq 'zztest-event2' -and $q1.Reason -match '领空') $q1.Reason
    Set-GdAckKey -Game 'ark' -Key 'zztest-event2'
    $q2 = Resolve-ArkPlan -S $S -Data $two -Source '假数据' -Now $nowMs
    Check 'A 已领空 → 自动改刷 B' ($q2.Mode -eq 'event' -and $q2.EventKey -eq 'zztest-event2' -and $q2.Reason -match '领空') $q2.Reason
    Set-GdShopDoneKey -Game 'ark' -Key 'zztest-event2'
    $q3 = Resolve-ArkPlan -S $S -Data $two -Source '假数据' -Now $nowMs
    Check '都领空 → 长草计划' ($q3.Mode -eq 'idle' -and $q3.ShopDone) $q3.Reason
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

# 2026-09-23 内部拆分：重试策略跟着"跑一轮"一起搬进了 lib\ark-daily.ps1，入口脚本只剩参数分发。
# 断言对象随之换文件，断言内容(那条跳过清单)一个字没改。
$arkDaily = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\ark-daily.ps1') -Raw -Encoding utf8
Check '方舟重试也会跳过 unknown-format' ($arkDaily -match "Status -notin @\('ok', 'not-started', 'unknown-format'\)")
# 2026-09-24 06:00 那一轮暴露的坑：重试前先 Stop-MaaAndGame(端游也一起关掉)，而"拉端游"那句写在重试闭包外面
# → 重试那轮只有 MAA 起来了、游戏没起来，MAA 只会报"未找到窗口"，白烧一轮。
# 这条是行为测试而不是文本比对：把 Start-GdArkDaily 用到的那几个动作换成假函数(定义在本函数局部作用域，
# 按 PowerShell 的动态作用域会盖掉脚本级同名函数)，数一遍"跑两轮"各拉了几次端游、跑了几次 MAA。
. (Join-Path $PSScriptRoot '..\lib\ark-daily.ps1')   # 编排层不在 test-lib 的点用清单里(test-lib 只点判定层+两个助手库)，这条要真调它
function Invoke-GdArkRetryProbe {
    $c = @{ launches = 0; maaRuns = 0; stops = 0; i = 0; statuses = @('stalled', 'ok') }
    function Start-Sleep { param([Parameter(ValueFromRemainingArguments)]$Rest) }   # 重试前真会睡 25 秒，自检里跳掉
    function Get-MaaPaths { param($S) return [pscustomobject]@{ Name = 'MAA' } }
    function Invoke-GdTakeover { param($S, $Names, $Label) }
    function Set-MaaDailyConfig { param($S, $Decision, [switch]$Apply) return [pscustomobject]@{ Changes = @(); ExpectedChains = @('StartUp') } }
    function Start-GdArkClient { param($S) $c.launches++; return $true }
    function Stop-MaaAndGame { param($S) $c.stops++ }
    function Invoke-MaaRun {
        param($S, $ExpectedChains)
        $c.maaRuns++; $st = $c.statuses[$c.i]; $c.i++
        return @{ Status = $st; Detail = "假状态 $st"; Duration = 1 }
    }
    function Get-GdInputDesktopName { return 'Default' }   # 起跑前置判定不许押机器现场：本机挂着屏保时这里会返回 Screen-saver，探针会被提前退掉判成"拉端游 0 次"的假红
    Start-GdArkDaily -S $S -Decision ([pscustomobject]@{ Mode = 'idle'; Stage = 'CE-5,LS-5'; ClearSanity = $true; Reason = '假判定' }) | Out-Null
    return [pscustomobject]@{ Launches = $c.launches; MaaRuns = $c.maaRuns; Stops = $c.stops }
}
$probe = Invoke-GdArkRetryProbe
Check '首轮 stalled 触发重试时，端游会被重新拉起(拉端游写在 $run 里，重试不再是光启动 MAA)' (
    $probe.MaaRuns -eq 2 -and $probe.Launches -eq 2) "拉端游 $($probe.Launches) 次 / 跑 MAA $($probe.MaaRuns) 次 / 收尾 $($probe.Stops) 次"
# 2026-09-26 起跑输入桌面判定的两条分支(同样全靠假函数，不看本机真桌面)：桌面被屏保/锁屏占住 → 早退 not-started、一次端游都不拉；
# 桌面名读不到('' = 不知道) → 不许据此杀正常路。
function Invoke-GdDeskGateProbe([string]$FakeDesk) {
    $c = @{ launches = 0; desk = $FakeDesk }
    function Start-Sleep { param([Parameter(ValueFromRemainingArguments)]$Rest) }
    function Get-MaaPaths { param($S) return [pscustomobject]@{ Name = 'MAA' } }
    function Invoke-GdTakeover { param($S, $Names, $Label) }
    function Set-MaaDailyConfig { param($S, $Decision, [switch]$Apply) return [pscustomobject]@{ Changes = @(); ExpectedChains = @('StartUp') } }
    function Start-GdArkClient { param($S) $c.launches++; return $true }
    function Stop-MaaAndGame { param($S) }
    function Invoke-MaaRun { param($S, $ExpectedChains) return @{ Status = 'ok'; Detail = '假ok'; Duration = 1 } }
    function Get-GdInputDesktopName { return $c.desk }
    $all = Start-GdArkDaily -S $S -Decision ([pscustomobject]@{ Mode = 'idle'; Stage = 'CE-5'; ClearSanity = $true; Reason = '假判定' })
    $r = @($all | Where-Object { $_ -is [System.Collections.IDictionary] }) | Select-Object -First 1
    return [pscustomobject]@{ Launches = $c.launches; Status = $r.Status; Detail = $r.Detail }
}
$gate = Invoke-GdDeskGateProbe -FakeDesk 'Screen-saver'
Check '输入桌面被屏保占住 → not-started 早退，一个端游不拉、Detail 带桌面名' (
    $gate.Launches -eq 0 -and $gate.Status -eq 'not-started' -and $gate.Detail -match 'Screen-saver') "拉端游 $($gate.Launches) 次 / 状态=$($gate.Status)"
$gate2 = Invoke-GdDeskGateProbe -FakeDesk ''
Check '读不到输入桌面名(空串=不知道) → 不早退，照常拉端游跑完' ($gate2.Launches -ge 1) "拉端游 $($gate2.Launches) 次"
$maaLib = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\maa.ps1') -Raw -Encoding utf8
Check 'MAA 侧也有 unknown-format 判定(日志在涨却零标志)' ($maaLib -match "Status = 'unknown-format'")

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
Check '停滞结论会把这条线索带上(不是只报"日志无输出")' (
    ($maaLib -match 'if \(\$asstHint\) \{ \$detail \+= '))
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

    # "点完画面到底变没变"必须用粗亮度签名，不能用文件哈希：端游背景有噪点动画，
    # 2026-09-24 那次 PostMessage 点完弹窗还在，却因为哈希不同被报成"救活了"。
    function SigWith($idxs, $val) { $a = @(1..144 | ForEach-Object { 20 }); foreach ($i in $idxs) { $a[$i - 1] = $val }; return ($a -join ',') }
    $shotA = [pscustomobject]@{ Sig = (SigWith @() 0) }
    $c0 = Test-GdShotChanged -Before $shotA -After $shotA
    Check '同一张画面 → 判"没变"' ($c0.Known -and -not $c0.Changed) $c0.Detail
    $c1 = Test-GdShotChanged -Before $shotA -After ([pscustomobject]@{ Sig = (SigWith @(7) 21) })
    Check '只有一格抖 1 档(噪点动画) → 仍判"没变"' (-not $c1.Changed) $c1.Detail
    $c2 = Test-GdShotChanged -Before $shotA -After ([pscustomobject]@{ Sig = (SigWith @(60, 61, 69, 70) 3) })
    Check '弹窗那一块整体暗下去 → 判"变了"' ($c2.Known -and $c2.Changed) $c2.Detail
    $c3 = Test-GdShotChanged -Before ([pscustomobject]@{ Sig = '' }) -After $shotA
    Check '拿不到签名(截图那步就没成)时不硬判' (-not $c3.Known -and -not $c3.Changed) $c3.Detail
    $fnShot = (Get-Command Save-GdWindowShot).Definition
    $fnClick = (Get-Command Send-GdArkClick).Definition
    $fnRescue = (Get-Command Invoke-GdVisionRescue).Definition
    Check '截图函数会带回 Sig(不然上面几条全是瞎的)' ($fnShot -match 'Sig = ')
    Check '点击走"抢前台 + 真实鼠标"，PostMessage 只当退路' (
        $fnClick -match 'TryForeground' -and $fnClick -match 'RealClick' -and $fnClick -match 'ClickOnce')
    # 2026-09-26 起兜底内核不认识端游了：截图/点击都向靶子要(lib\vision-ark.ps1 的 New-GdVisionTarget-ark)。
    # 所以这里判两件事：内核里**不能**再出现端游那三个动作，而靶子必须把它们接上 —— 少一头就是"兜底静默不生效"。
    $fnTarget = (Get-Command New-GdVisionTarget-ark).Definition
    Check '兜底内核只向靶子要 Shot/Click，不再自己拍端游窗口、自己点端游' (
        $fnRescue -match '\$t\.Shot' -and $fnRescue -match '\$t\.Click' -and
        $fnRescue -notmatch 'Send-GdArkClick|ClickOnce|PostMessage|PrintWindow|Get-GdArkWindow')
    Check '端游靶子把 Shot/Click 接到 Save-GdWindowShot / Send-GdArkClick 上' (
        $fnTarget -match 'Save-GdWindowShot' -and $fnTarget -match 'Send-GdArkClick')
    Check '最小化的窗口会先 SW_RESTORE 再拍(否则拍到的是 168x29 空位图)' (
        $fnShot -match 'IsIconic' -and $fnShot -match 'Restore')

    # 复制 + 改值都走通用工具(Set-GdMapValue 用 Add-Member -Force)：直接写 $obj.arkVisionRescue = $false
    # 在这份 settings 里没有这个键时会抛"找不到属性"，而导出仓库的模板恰恰可能没给。
    $runtimeOff = [pscustomobject](Convert-GdMapToHashtable $S.runtime)
    Set-GdMapValue -Map $runtimeOff -Key 'arkVisionRescue' -Value $false | Out-Null
    $r0 = Invoke-GdVisionRescue -S ([pscustomobject]@{ runtime = $runtimeOff; paths = $S.paths })
    Check 'arkVisionRescue=false → 一次都不试' (-not $r0.Tried -and -not $r0.Done -and $r0.Detail -match 'arkVisionRescue') $r0.Detail
    # 前置条件不满足的两条闸门都排在"截图"之前 → 这一条既不会联网也不会拍窗口，不管当前是不是管理员
    $runtimeNoKey = [pscustomobject](Convert-GdMapToHashtable $S.runtime)
    Set-GdMapValue -Map $runtimeNoKey -Key 'visionApiKey' -Value '' | Out-Null
    $savedKey = $env:DASHSCOPE_API_KEY
    $env:DASHSCOPE_API_KEY = ''
    $r1 = Invoke-GdVisionRescue -S ([pscustomobject]@{ runtime = $runtimeNoKey; paths = $S.paths })
    $env:DASHSCOPE_API_KEY = $savedKey
    Check '没提权或没 key → 直接放弃，不截图也不调模型' (
        -not $r1.Tried -and -not $r1.Done -and $r1.Detail -match '权限|key') $r1.Detail
    Check '停滞判定处挂了兜底，且用 Get-Command 探路(单游戏仓库没这文件也能跑)' (
        $maaLib -match 'Get-Command Invoke-GdVisionRescue' -and $maaLib -match 'Invoke-GdVisionRescue -S \$S')

    # 2026-09-26：一次问价拿到的 3 个点位在这里按把握逐个试。为什么值得逐个试 ——
    # 实测模型认得弹窗、却把 × 认成旁边那个"暂不查看"，只给一个点位时"点完没动"就只能整轮放弃；
    # 而三个点位来自同一次问价：不额外花钱、不额外等模型，也不会出现"换个答案把上一个还回去"。
    Check '兜底改成按候选点位逐个试的循环，每个点位点完都补拍一张再比' (
        $fnRescue -match 'foreach \(\$pt in \$points\)' -and $fnRescue -match '-after' -and
        $fnRescue -match 'Test-GdShotChanged')
    Check '落不到画面里的候选先全部剔掉，一个不剩就直接放弃(不在真点击时才发现点位在标题栏上)' (
        $fnRescue -match '\$points = @\(foreach' -and $fnRescue -match 'if \(-not \$points\.Count\)')
    Check '试完最后一个点位仍没动 → 说清"点了几个候选、画面都没动"' (
        $fnRescue -match '候选点位' -and $fnRescue -match '画面都没动')
    Check '救火账本由调用方点，内核自己不记(内核不知道自己是给哪一路兜的)' (
        $fnRescue -notmatch 'Add-GdRescueRecord')
    # 上下文：同一张画面，带不带"卡在哪个任务、重复点了多少次"，模型挑出的挡路货不一样，
    # 而兜底一轮就那么几次机会 —— 问得准比问得省重要。
    $fnRaw = (Get-Command Invoke-GdVisionRaw).Definition
    $fnAsk = (Get-Command Invoke-GdVisionAsk).Definition
    Check '问价那一层把自动化的处境拼进用户那句话，并且截到 200 字(不塞日志原文)' (
        $fnRaw -match '自动化这边的处境' -and $fnRaw -match '200')
    Check '-Context 一路从兜底入口递到问价层，中间不断线' (
        $fnRescue -match 'Invoke-GdVisionAsk.*\$Context' -and $fnAsk -match 'Invoke-GdVisionRaw.*\$Context')
    Check '方舟这三个兜底调用点各自往救火账本记一笔(-Game ark)' (
        ([regex]::Matches($maaLib, 'Add-GdRescueRecord -S')).Count -eq 3 -and
        ([regex]::Matches($maaLib, "-Game 'ark'")).Count -eq 3) $(
        "记了 $([regex]::Matches($maaLib, 'Add-GdRescueRecord').Count) 笔")
    Check '早触发和跑空兜底都带上下文(停滞那句说清卡在哪个子任务)' (
        $maaLib -match '-Context \$whyStuck' -and $maaLib -match '只完成 ')
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
    $typeDef = (Get-Command Add-GdRescueTypeDef).Definition
    Check '桌面名走 OpenInputDesktop + UOI_NAME，用完关掉句柄' (
        $typeDef -match 'OpenInputDesktop' -and $typeDef -match 'GetUserObjectInformationW' -and $typeDef -match 'CloseDesktop')
    Check '探测还能说清"谁占着前台"，并且读窗口自身状态(最小化/可见/矩形)' (
        $typeDef -match 'GetWindowThreadProcessId' -and $typeDef -match 'IsWindowVisible' -and
        $typeDef -match 'WindowRectText')
    Check '抢前台只动窗口状态，绝不往客户区点一下，并把现场带回 Detail' (
        $fnGrab -match 'TryForeground' -and $fnGrab -notmatch 'RealClick' -and $fnGrab -notmatch 'ClickOnce' -and
        $fnGrab -match 'st\.Detail')
    Check 'MAA 那一路的早退改按"同一子任务重试次数"判，且那句错话已经从代码里删掉' (
        $maaLib -match '\$stuckExec -ge 60' -and $maaLib -match 'Invoke-GdArkForegroundGrab' -and
        $maaLib -notmatch '点击通道已退化' -and $maaLib -match 'Get-Command Get-GdArkDesktopState')
    # #17 早触发：抢前台只解决"窗口收不到输入"这一种；另一种是"模板集里没收录的界面挡在路上"，
    # 那只能问画面。所以抢完前台立刻问一次 —— 那 60 秒本来也不会自己变好，干等 22 分钟更不值得。
    $iStuck = $maaLib.IndexOf('if (($stuckExec -ge 60)')
    $iDrain2 = $maaLib.IndexOf('if ($drained -and -not $allDone)')
    $blockStuck = if ($iStuck -gt 0 -and $iDrain2 -gt $iStuck) { $maaLib.Substring($iStuck, $iDrain2 - $iStuck) } else { '' }
    Check '抢到前台之后当场问一次画面(不再只抢不问)' (
        $blockStuck -match 'Invoke-GdArkForegroundGrab' -and $blockStuck -match 'Invoke-GdVisionRescue') "stuck@$iStuck drain@$iDrain2"
    Check '这一问排在"静默 22 分钟"那条判定之前(排在后面就等于没加)' (
        $iStuck -gt 0 -and $iDrain2 -gt $iStuck -and $maaLib.IndexOf('if ($quiet -gt $stall)') -gt $iDrain2)
    Check '早触发也受同一份预算管($rescueLeft)，且用 Get-Command 探路' (
        $blockStuck -match '\$rescueLeft -gt 0' -and $blockStuck -match '\$rescueLeft--' -and
        $blockStuck -match 'Get-Command Invoke-GdVisionRescue')
    Check '早触发把"为什么觉得它卡住"原话带给模型(卡在哪个子任务、重复点了多少次)' (
        $blockStuck -match '重复点了' -and $blockStuck -match '-Context \$whyStuck')
    Check '兜底结论拼进这一轮的救援记录，同时记进救火账本' (
        $blockStuck -match '\$rescues \+= \$rc\.Detail' -and $blockStuck -match 'Add-GdRescueRecord')
} else {
    Check 'lib\vision-rescue.ps1 存在(方舟仓库少了它探测就不生效)' $false '没找到 Get-GdArkDesktopState'
}

Write-Host "`n[t15] MAA 自己把队列跑空了，别再傻等 22 分钟(2026-09-25 07:53 那轮现场暴露的)"
# 那一轮 asst.log 里 5 次点击全部落地(START 一点就过、还关掉了两张弹窗)，随后
# StartUp@CloseAnno 连认 50 次认不出「锦枫映月」的 ×，公招/基建/作战/商店/奖励 6 条链路 0 完成，
# 07:56:46 gui.log 打出「任务已完成，但出现错误！」= MAA 的队列已经空了、它不会再自己动。
# 老代码只认「任务已全部完成」，于是这一种收尾一路等到「asst.log 静默 22 分钟」才反应，
# 而那时候就算把挡路窗口关掉也没人接着跑 —— 白等 22 分钟。
Check '认下「跑完但有错误」这句收尾，并置 $drained' (
    $maaLib -match '任务已完成，但出现错误' -and $maaLib -match '\$drained = \$true')
Check '队列跑空且链路没跑齐 → 当场兜底，不等静默判定' (
    $maaLib -match '\$drained -and -not \$allDone')
# 把这一段单独切出来判：这一段只准"兜底一次 + 早退"，重启端游/重起 MAA 是外层重试干的事
$iDrain = $maaLib.IndexOf('if ($drained -and -not $allDone)')
$iQuiet = $maaLib.IndexOf('if ($quiet -gt $stall)')
$blockDrain = if ($iDrain -gt 0 -and $iQuiet -gt $iDrain) { $maaLib.Substring($iDrain, $iQuiet - $iDrain) } else { '' }
Check '这段判定排在"静默 22 分钟"之前(顺序错了就等于没改)' (
    $iDrain -gt 0 -and $iQuiet -gt $iDrain) "drain@$iDrain quiet@$iQuiet"
Check '跑空后先当场兜底一次(有视觉兜底函数才兜，$rescueLeft 限次数)' (
    $blockDrain -match 'Invoke-GdVisionRescue' -and $blockDrain -match '\$rescueLeft--')
Check '这一轮不做原地重启：关端游重开 + 重起 MAA 是外层那一次重试的事(2026-09-25 08:4x 实测走的正是那条路)' (
    $blockDrain -notmatch 'Stop-Process' -and $blockDrain -notmatch 'Start-Process' -and
    $blockDrain -notmatch 'Stop-MaaAndGame' -and $blockDrain -notmatch 'Start-GdArkClient')
Check '兜过没兜成都一律立刻早退成 stalled，并说明外层会重试一次(不再清零计时继续等)' (
    $blockDrain -match "Status = 'stalled'" -and $blockDrain -match '外层会重试一次' -and
    $blockDrain -notmatch '(?im)^\s*continue\s*$')

Write-Host "`n[t16] 救火账本 + 只问不点的诊断入口(2026-09-26 加强 AI 干预时加的，全程不联网、不起子进程)"
if (Get-Command Add-GdRescueRecord -ErrorAction SilentlyContinue) {
    # 这本账回答的是"哪一路、哪个环节、兜完画面到底变没变"，和 ask.py 那本接口账(state\vision\calls.jsonl)分开放。
    # 它会真写 state\rescue.json，所以照 t7 的规矩先存后还原。
    Save-GdTestState -Names @('rescue')
    try {
        # 先把它删掉：**第一次**救火时这本账压根不存在，而 Read-GdJson 对"文件不存在"是 throw，
        # 入口又是 $ErrorActionPreference='Stop' —— 不先测这一条，"记一笔账"能把整轮日常弄挂(2026-09-26 就是这么红出来的)。
        Remove-Item -LiteralPath (Get-GdRescueLedgerPath) -Force -ErrorAction SilentlyContinue
        # -S 在这条路上只是"要不要写得出账"的旁观者(它连 settings 都不读)，给个空壳就够
        $noCfg = [pscustomobject]@{ runtime = [pscustomobject]@{} }
        $firstOk = $true
        try {
            [void](Add-GdRescueRecord -S $noCfg -Game 'ark' -Target 'ark' -Tag 'first' `
                    -Result ([pscustomobject]@{ Tried = $false; Done = $false; Detail = '账本还没有，第一次记一笔' }))
        } catch { $firstOk = $false; Write-Host "  第一次记账就抛了：$($_.Exception.Message)" -ForegroundColor Red }
        Check '账本文件还不存在时也能记下第一笔(不把"记账"升级成"整轮失败")' $firstOk
        $fnLedger = (Get-Command Add-GdRescueRecord).Definition
        Check '记账前先看文件在不在(Read-GdJson 对缺文件是 throw，裸调就是上面那条)' (
            $fnLedger -match 'Test-Path -LiteralPath \$path')
        [void](Add-GdRescueRecord -S $noCfg -Game 'ark' -Target 'ark' -Tag 'stuck1' `
                -Result ([pscustomobject]@{ Tried = $true; Done = $false; Detail = "第一行`n第二行(换行要被压平)" }))
        [void](Add-GdRescueRecord -S $noCfg -Game 'r1999' -Target 'mumu' -Tag 'm9a1' `
                -Result ([pscustomobject]@{ Tried = $true; Done = $true; Detail = '已按模型判断关掉活动弹窗' }))
        $led = Read-GdJson -Path (Get-GdRescueLedgerPath)
        Check '账本落在 state\rescue.json，一次兜底一行' ($led -and @($led.events).Count -eq 3) "实际 $(@($led.events).Count) 条"
        Check '归属(game/target/tag)由调用方写进去(内核不知道自己是给哪一路兜的)' (
            $led.events[1].game -eq 'ark' -and $led.events[1].target -eq 'ark' -and
            $led.events[2].game -eq 'r1999' -and $led.events[2].target -eq 'mumu') $(
            "$($led.events[1].game)/$($led.events[1].target) + $($led.events[2].game)/$($led.events[2].target)")
        Check '兜没兜成是两个独立的 bool(试过 ≠ 救活)' (
            $led.events[1].tried -and -not $led.events[1].done -and $led.events[2].done) $(
            "$($led.events[1].tried)/$($led.events[1].done) vs $($led.events[2].tried)/$($led.events[2].done)")
        Check 'detail 里的换行压平成一行(账本是给人翻的，不是日志归档)' (
            $led.events[1].detail -notmatch "`n" -and $led.events[1].detail -match '\|') $led.events[1].detail
        # 裁剪：这是一本"回看上几轮"的账，不是日志。留最近的，砍最老的。
        for ($i = 1; $i -le 8; $i++) {
            [void](Add-GdRescueRecord -S $noCfg -Game 'ark' -Result ([pscustomobject]@{ Tried = $false; Done = $false; Detail = "凑数 $i" }) -Keep 5)
        }
        $led2 = Read-GdJson -Path (Get-GdRescueLedgerPath)
        Check '超过 Keep 条就砍最老的(这里只留最近 5 条)' (@($led2.events).Count -eq 5 -and @($led2.events)[-1].detail -match '凑数 8') $(
            "$(@($led2.events).Count) 条，最后一条=$(@($led2.events)[-1].detail)")
        $fnLedger = (Get-Command Add-GdRescueRecord).Definition
        Check '账本写不进去只是 WARN 一句，不抛(异常路径上不许再制造一个异常)' (
            $fnLedger -match 'try \{ Write-GdJson' -and $fnLedger -match '-Level WARN')
    } finally { Restore-GdTestState }
    Check 'state 文件已还原' (Test-GdTestStateRestored)
} else {
    Check 'lib\vision-rescue.ps1 有 Add-GdRescueRecord(方舟仓库少了它这轮救火没人知道)' $false '没找到这个函数'
}

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
$farmLib = Join-Path $PSScriptRoot '..\lib\ark-farm.ps1'
if (Test-Path -LiteralPath $farmLib) { . $farmLib }   # 记账/判定层和 ark-daily 一样不在 test-lib 的点用清单里，这条自己点；文件不在(工程被裁)交给下面的守卫说人话
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
    # 目标30 现有18 差12；p1 显式填了 CE-5 → 只按 CE-5 的学习数据算：12/5=2.4 → ceil(12/2.4)=5 场
    Check 'farm 判表：缺口=目标-现有，学习表挑关(最多2、平均掉得多的打头)' ($rf.Active -and [int]$rf.Gap -eq 12 -and @($rf.Stages).Count -le 2 -and $rf.Stages[0] -eq 'CE-5') ($rf.Stages -join ',')
    Check 'farm 判表：次数按学习到的掉落率折算且 Reason 说清账目' ([int]$rf.Times -eq 5 -and $rf.Reason -match '还差 12' -and $rf.Reason -match '每场约 2\.4') $rf.Reason
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
