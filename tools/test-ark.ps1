# tools/test-ark.ps1 — 明日方舟那一路的纯逻辑自检(只读：不改配置、不启动任何程序)
# 用法: pwsh -NoProfile -File tools\test-ark.ps1
# 1999 那一路在 tools\test-r1999.ps1；两边都跑就依次直调这两本(各本自己的退出码说话)。
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
# 三枚旧读件与 Test-GdShopDoneEnabled 已出仓，锚换家到 Resolve-ArkPlan 组值半段；剥注释两形照 test-r1999(-replace 逐字复用)：
# 不剥注释的正向锚会在真身被摘掉后照样绿——在册的「锚不是调用」形。
$fnPlan = [string](Get-Command Resolve-ArkPlan -ErrorAction SilentlyContinue).Definition
$fnPlan = ($fnPlan -replace '(?s)<\#.*?\#>', ' ') -replace '(?m)^\s*#.*$', ' '
# 刀㉑ 笔(b)-1(2026-11-08)改口：组值半段现问 compose-decision-inputs 一次取齐，「给不给领空图」的折算真身进核(可选入键 ignoreShopDone)，本壳不再有 FlagEnabled 表达式与 read-decision-state 那次问；read-decision-state 本身仍在位(Show-GdGateState／门侧夹具在吃)，其出仓另族。
Check '刀㉑ 笔(b)-1 核臂在：Resolve-ArkPlan 现问 compose-decision-inputs 一次取齐(旧三枚读件与那次 read-decision-state 都不再出现在组值半段)' (
    $fnPlan.Contains("Invoke-GdCli -Verb 'compose-decision-inputs'") -and
    -not $fnPlan.Contains('read-decision-state') -and
    -not $fnPlan.Contains('Get-GdAckMap') -and -not $fnPlan.Contains('Get-GdShopDoneMap') -and -not $fnPlan.Contains('Test-GdShopDoneEnabled')) $(
    if ($fnPlan.Length -eq 0) { 'Resolve-ArkPlan 不在场(尺没接到电)' } else { "len=$($fnPlan.Length)" })
Check '刀㉑ 笔(b)-1 折算在核：组值半段只传可选入键 ignoreShopDone，领空吃核交回的 $ci.ShopDone(PS 侧不再有 FlagEnabled 与 ShopDoneGateOpen)' (
    $fnPlan.Contains('ignoreShopDone = [bool]$IgnoreShopDone') -and $fnPlan.Contains('$ci.ShopDone') -and
    -not $fnPlan.Contains('$ds.ShopDoneGateOpen') -and -not $fnPlan.Contains('FlagEnabled')) $('len=' + $fnPlan.Length)

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
# 11-08 刀㉓ 笔(b) 第三子批 第十一刀：三枚行为格整批出仓，留「关卡表非空」——它量本机 resource\stages.json 现况，不属 verb 答法族。
#   对面＝Decisions.SelfTest.cs check-stages 四枚(混分隔／理智合计／未知关卡点名／单关卡话术)，判据收到逐字段等值。
$table = Get-GdStageTable -S $S
Check '关卡表非空' ($table.Count -gt 300) "$($table.Count) 条"

Write-Host "`n[t3] MAA 队列改写(仅预览，不落盘)"
# 11-08 刀㉓ 笔(b) 第三子批 第十一刀：九枚 apply-maa-daily-config 行为格与五块取数整批出仓。对面＝Round.SelfTest.cs 第 28 节五枚
#   (keep/turnOff 拦下・预览 SHA-256 前后相同且 Changes 非空・event-pending 不烧理智・event 档写 SR-8・长草坏关卡整句等值)；证牙四发见 docs §11.312。

Write-Host "`n[t5] 方舟判定链路(会联网拉一次活动接口)"
# ---- 刀⑯ 收官批 笔(b)(11-06)：Get-ArkEvent 出仓，取数半段改问核(换答方不换问法) ----
# 组合式＝Get-GdNowMs(现场时钟留壳§9-2) + read-ark-activity(三档与 WARN 原话在 Round.Data.cs::ArkActivity) + Lines 回放 + Resolve-ArkPlan；
# 转发壳只传可选入键 ignoreShopDone(刀㉑ 笔(b)-1 起领空折算真身在核 compose-decision-inputs)。
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

Write-Host "`n[t7] 商店领空写面(set-ark-shop-state 的 reset 臂 + state 快照还原)"
# 刀㉑ 笔(b)-2(11-08)：原 19 枚判定面整族换家核侧，摘前七发 mutation 证牙(三发折图／四发 Decisions.Ark 话术与回落臂，MUT=7/7；§11.294 挂的两发由本批 R2/R3 结清)。对面坐标……（细节见该帧）
Save-GdTestState -Names @('ark-shop-done')
# 诚实登记：PS 侧 -IgnoreShopDone 的行为级正对照随「可回看原结论」那枚出仓，只剩 :31-33 静态锚；行为证词的家在 roundtest 第 34) 节。
try {
    Invoke-GdCli -Verb 'set-ark-shop-state' -Body ([pscustomobject]@{ eventKey = 'zztest-event'; eventTip = '测试'; done = $true }) | Out-Null
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

# 09-23 内部拆分：重试策略随「跑一轮」搬进 lib\ark-daily.ps1；10-24 刀③ 把 PS 回退臂整段出仓后，这里的桌子跟着换：
# 跳过清单的家＝panel-cs\Orchestration.cs 的 DailyRetry ark 支(verb decide-daily-retry，-Game ark)；「重试轮必须重开端游」「读不到桌面名不许杀正常路」
# 两条行为的家＝main.rs --selftest 第 29 节(见下面六格静态锚)。断言内容一字未改：三枚状态名一枚不许少，正则取空窗一律红(fail-closed)。
$orchArkCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Orchestration.cs') -Raw -Encoding utf8
$arkRetryWin = [regex]::Match($orchArkCs, '(?s)if \(EqS\(game, "ark"\)\)(?<win>.*?)else if \(EqS\(game, "r1999"\)\)').Groups['win'].Value
Check '方舟重试也会跳过 unknown-format' (($arkRetryWin -match '"ok"') -and ($arkRetryWin -match '"not-started"') -and ($arkRetryWin -match '"unknown-format"') -and ($arkRetryWin -match '收尾后重试一次'))
# 11-04 笔(c/d) 作废登记①：原来这里 dot 一份 lib\ark-daily.ps1(编排岛)。那件整件出仓，这条 dot 随它一起没了…（细节见该帧）
$arkRoundPs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\rust-round.ps1') -Raw -Encoding utf8
$arkRoundCode = ($arkRoundPs -replace '(?s)<\#.*?\#>', ' ') -replace '(?m)^\s*#.*$', ' '
$arkCoreRs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rustcore\src\main.rs') -Raw -Encoding utf8
$arkVisionCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Vision.SelfTest.cs') -Raw -Encoding utf8
Check 'arkdrive 门两档的行为判据已在核内 --selftest 第 29 节(门退役后尺住在代码里)' (
    ($arkCoreRs.Contains('第 29 节：arkdrive 门退役四组真空档补尺')) -and ($arkCoreRs.Contains('C-retry-relaunch')) -and
    ($arkCoreRs.Contains('C-desk-empty-vs-early')))
# 11-04 笔(c/d) 作废登记②：原三格(ask 白名单十一枚／run·mark·obsrec·admin 四 case／信封 role 字面 R3-drive-ark-daily)量的是编排岛驱动档 executor 源码形状；…（细节见该帧）
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
# 负锚那副眼镜跟着搬家：直身件里 visionApiKey 的命中现拍全在注释里(讲"整块 runtime 里住着 key"那处)……（细节见该帧）
Check '直身件的代码面一个字都不碰视觉 API key(visionApiKey 不许进 ctx 那本留盘的账；负锚按剥注释后抓)' (
    (-not $arkHostCode.Contains('visionApiKey')) -and ($arkHostCs.Contains('visionApiKey')))
# 「退役不回潮」那枚(形状照下面编排岛名册那一格；名册由 foreach 供数，注释不写枚数)：PS 侧自此只递旋钮……（细节见该帧）
$arkCtxDefBad = @()
foreach ($arkCtxFn in @('Get-GdRoundCtx', 'Get-GdRoundMaaRunPayload', 'Get-GdRoundM9aRunPayload')) {
    if ($arkRoundCode.Contains('function ' + $arkCtxFn + ' {')) { $arkCtxDefBad += $arkCtxFn }
}
$arkCtxVerbHits = [regex]::Matches($arkRoundCode, "Invoke-GdCli -Verb 'build-round-ctx'").Count
Check '轮档件的 PS 侧不再自己装配 ctx(三枚定义不许回潮；装配只走 build-round-ctx 那一枚出口且调用点唯一)' (
    ($arkCtxDefBad.Count -eq 0) -and ($arkCtxVerbHits -eq 1)) (((($arkCtxDefBad -join ',') + '|verb-hits=' + $arkCtxVerbHits)))
# 10-27 甲档第四刀刀②：Invoke-MaaRun 真身(lib\maa.ps1 旧 :220-620)整函数出仓——循环骨架进核(maa_run + RealHost，main.rs)……（细节见该帧）
Check 'arkrun 门 27 档等值面已在核内 --selftest 第 30 节(门退役后尺住在代码里)' (
    ($arkCoreRs.Contains('30. arkrun 27 档金样回放')) -and ($arkCoreRs.Contains('K20_GOLDEN')) -and
    ($arkCoreRs.Contains('K20_EXTRA')))
Check '第 30 节的名册与形状是两份独立事实源(不从金样反推＝第十五刀那条恒真尺防线)' (
    ($arkCoreRs.Contains('const K20_NAMES: [&str; 27] = [')) -and ($arkCoreRs.Contains('const K20_VERBS: [&str; 14] = [')) -and
    ($arkCoreRs.Contains('K20_SHAPE')))
# 10-28 第二十刀刀③：lib\vision-rescue.ps1 兜底编排六枚(169 函数行)整件出仓，t13/t16 那 20 枚随壳侧退役(搬家账见 §11.165)。
$vrRevived = @()
foreach ($vrFnName in @('Invoke-GdVisionRescue', 'New-GdRescueSkip', 'Clear-GdRescueShotDir', 'Get-GdRescueLedgerPath', 'Test-GdShotChanged', 'Add-GdRescueRecord')) {
    if (Get-Command $vrFnName -ErrorAction SilentlyContinue) { $vrRevived += $vrFnName }
}
$vrSixTooth = (@($vrRevived).Count -eq 0)
# ⚠ 11-06 自伤更正(纪律留着)：detail 曾读一枚从没设过的脚本变量，strict mode 当场抛「无法检索变量」——最该安静的走法走成炸门。
$vrSixWhy = $(if (@($vrRevived).Count -gt 0) { '件已不在，但这几枚以命令形态复活：' + ($vrRevived -join ',') } else { '' })
Check '兜底编排六枚的定义不在现树 PS 侧(双删是回归抓器：编排只住核内 vision_rescue 一处；咬命令复活)' $vrSixTooth $(
    if ($vrSixWhy) { $vrSixWhy } else { '六枚命令名册现读为空' })
Check '刀③ 补尺两枚住在核内第 19 节(链不记帐 / context 原样递到问价层)' (
    ($arkCoreRs.Contains('第二十刀刀③ 补尺①')) -and ($arkCoreRs.Contains('第二十刀刀③ 补尺②')))
Check '画面变没变的四形与 detail 压平两形住在 C# 自检里(Vision.SelfTest.cs 接守 t13/t16 摘下的那两族)' (
    ($arkVisionCs.Contains('只有一格抖 1 档')) -and ($arkVisionCs.Contains('两次画面格数不同')) -and
    ($arkVisionCs.Contains('detail 换行压平')))

# ── 转接刀·方舟拉起族(11-03)补尺格：三处消费面各自现问两枚核内出口 ──────────────…（细节见该帧）
$arkModulePs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\ark-module.ps1') -Raw -Encoding utf8
# 11-04 笔(c/d) 作废登记③：上面那三格拉链(拉起答臂只认 Started／链体答臂问 stop-maa-and-game／Lines 回放)钉的是编排岛 executor 怎么取回执；…（细节见该帧）
$arkIslandBad = @()
foreach ($arkIslandFn in @('Set-GdArkShopState', 'Resolve-GdArkDecision', 'Show-GdArkPreview', 'Start-GdArkDaily', 'Get-GdArkDriveExe', 'Invoke-GdArkDailyRust')) {
    if ($arkRoundPs.Contains('function ' + $arkIslandFn + ' ') -or $arkModulePs.Contains('function ' + $arkIslandFn + ' ')) { $arkIslandBad += $arkIslandFn }
}
Check '编排岛真身的定义不在轮档件与清单件里(名册逐枚现扫；回潮＝核内一份＋PS 一份那本双账复活；运行面唯一一条腿是 daily-clear→rust-round→--daily-round)' ($arkIslandBad.Count -eq 0) ($arkIslandBad -join ',')
# 「退役不回潮」负锚(形状照刀③)：lib\maa.ps1 三枚真身(Wait-GdArkLauncherReady／Start-GdArkClient／Stop-MaaAndGame)出仓后，
# 唯一事实源在 Chain.cs；这一格不防功能缺失(功能由核内自检钉)，只防「有人把定义搬回 PS 侧」那本双账复活。
$arkMaaPs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\maa.ps1') -Raw -Encoding utf8
Check '拉起族三枚真身的定义不在现树 PS 侧(双删是回归抓器：起进程／启动器页／进程树收尾只住核内 Chain.cs 一处)' (
    (-not $arkMaaPs.Contains('function Wait-GdArkLauncherReady ')) -and
    (-not $arkMaaPs.Contains('function Start-GdArkClient ')) -and
    (-not $arkMaaPs.Contains('function Stop-MaaAndGame ')))
# 刀⑨「退役不回潮」负锚：五枚 AST 零调用死真身里这一路看得见的四枚——common 的 Invoke-GdTakeover／Get-GdWindowByTitle 与
# maa 的 Get-GdMaaFightSkip／Get-GdMaaStageObservation——判据本体早在历刀进核(Orchestration.cs 两枚 detect／observe，对面读盘与接管在 Chain.cs)。
# 名册由 foreach 供数，注释不写死枚数(在册：帧的历史可写死，树的现量只能供数)。
$arkCommonDeadPs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\common.ps1') -Raw -Encoding utf8
$arkCut9Bad = @()
foreach ($arkCut9Fn in @('Invoke-GdTakeover', 'Get-GdWindowByTitle', 'Get-GdMaaFightSkip', 'Get-GdMaaStageObservation')) {
    if ($arkCommonDeadPs.Contains('function ' + $arkCut9Fn + ' ') -or $arkMaaPs.Contains('function ' + $arkCut9Fn + ' ')) { $arkCut9Bad += $arkCut9Fn }
}
Check '刀⑨ 四枚死真身的定义不在现树 PS 侧(common 与 maa 两件按名册逐枚现扫；回潮＝零调用尺白跑，判据只住核内与 Chain.cs)' ($arkCut9Bad.Count -eq 0) ($arkCut9Bad -join ',')

Write-Host "`n[t12] asst.log 停滞线索(gui.log 静默时唯一看得见的东西)"
# 11-08 刀㉓ 笔(b) 第三子批 第十刀：四枚 verb 直答行为格(点名卡住的子任务／认不出不编造／空文本不炸／刚开始不算反复点击)与两份输入块整批出仓。
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
# 11-06 刀⑮ 笔(d)：本节原二十二枚行为格真调 vision-rescue／vision-ark 腹内六枚；三件本体出仓后，这二十二枚由覆盖面尺…（细节见该帧）
$rescueOnDisk = Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\lib\vision-rescue.ps1')
Check '兜底内核件与 Get-GdVisionVerdictFromText 命令同一个事实(同在同不在，半迁移红)' (
    $rescueOnDisk -eq [bool](Get-Command Get-GdVisionVerdictFromText -ErrorAction SilentlyContinue)) "件=$rescueOnDisk"
# 2026-11-08 刀㉕ 笔(a)：原先这里有一格量 Vision.cs 源文本的六串(只回 JSON／千分比／clicks 最多 3 个／按把握排／
#   关闭类按钮／绝对不要给)。判据不删只换家 ⇒ 六串全在 --visiontest 的 PromptGroup 里逐格重跑(只回 JSON＋千分比
#   一格、规则 2 整行逐字一格、规则 3 两格)，其中「按把握排」「关闭类按钮」两串本批补成整行逐字才摘。按刀③
#   「把真调换成钩子格还在的形钉等于给壳续命」，源文本形钉直接删格，不换取法重写。
$liveCsT13 = ''
try { $liveCsT13 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Live.cs') -Raw -Encoding utf8 } catch { }
Check '端游截图与点击那半的规矩住在核侧(带回 Sig、最小化先 SW_RESTORE、抢不到前台才退 PostMessage)' (
    $liveCsT13.Length -gt 0 -and $liveCsT13.Contains('"Sig"') -and $liveCsT13.Contains('IsIconic') -and
    $liveCsT13.Contains('SW_RESTORE') -and $liveCsT13.Contains('TryForeground') -and
    $liveCsT13.Contains('RealClick') -and $liveCsT13.Contains('ClickOnce')) ("Live.cs=" + $liveCsT13.Length + " 字符")
# 刀⑰ 笔(c)-2 第 1 批 B1 换家(§11.276)：老形是 PS 侧 Get-Content -Raw 读整本 Cli.cs，再逐枚手拼…（细节见该帧）
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
# 2026-11-08 刀㉕ 笔(a)：原先这里有一格量 Vision.SelfTest.cs 的六枚格名在场(钩子格还在的形钉)。按刀③ 直接删格：
#   那六族判语每次跑 --visiontest 都被真跑一遍(抠件／点位上限／越界拒／端点补全／桌面态／画面签名)，钉文本不如钉结果；
#   且钉文本这格本身就是「钩子格还在＝覆盖还在」的假安心。
if (-not $rescueOnDisk) {
    Check 'PS 侧那六枚兜底真身没在现树复活(问价／解析／提示词／端点／换算／截图签名)' (
        -not (Get-Command Get-GdVisionVerdictFromText -ErrorAction SilentlyContinue) -and
        -not (Get-Command Get-GdVisionSystemPrompt -ErrorAction SilentlyContinue) -and
        -not (Get-Command Resolve-GdVisionEndpoint -ErrorAction SilentlyContinue) -and
        -not (Get-Command Get-GdRescueClickPoint -ErrorAction SilentlyContinue) -and
        -not (Get-Command Invoke-GdVisionRaw -ErrorAction SilentlyContinue) -and
        -not (Get-Command Save-GdWindowShot -ErrorAction SilentlyContinue))
    # 2026-11-08 刀㉕ 笔(a)：原先这里有一格量 Live.cs 与 Live.SelfTest.cs 的源文本(自动化这边的处境／Substring(0, 200))。
    #   判据不删只换家 ⇒ Live.SelfTest.cs 268/273 两格按行为重跑(拼处境整句等值＋200 字截断金样)，比源文本 -and 强一档。
}

Write-Host "`n[t14] 点了没动怎么说、怎么早退(2026-09-25 一天里两次改口的教训都在这里)"
# 09-25 06:00 那轮真凭据：MAA 每 4 秒往 splash 的 START 点一下、点到 exec_times=311，模板分始终 0.99，画面一动不动。当年第一版把原因写成…（细节见该帧）
$arkVisionFileOnDisk = Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\lib\vision-ark.ps1')
Check '端游视觉后端件与 Get-GdArkDesktopState 命令同一个事实(同在同不在，半迁移红)' (
    $arkVisionFileOnDisk -eq [bool](Get-Command Get-GdArkDesktopState -ErrorAction SilentlyContinue)) "件=$arkVisionFileOnDisk"
$gdWinCs = ''
try { $gdWinCs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\tools\gdinterop\GdWin.cs') -Raw -Encoding utf8 } catch { }
Check '桌面名走 OpenInputDesktop + UOI_NAME，用完关掉句柄(名单只在 tools\gdinterop\GdWin.cs 里)' (
    $gdWinCs.Length -gt 0 -and $gdWinCs -match 'OpenInputDesktop' -and $gdWinCs -match 'GetUserObjectInformationW' -and
    $gdWinCs -match 'CloseDesktop') ("GdWin.cs={0} 字符" -f $gdWinCs.Length)
# 2026-11-08 刀㉑ 笔(c)：上面这枚格原还带一条合取「也不许内联回 PS 那份」，那是**哑的**——它咬的是…（细节见该帧）
$libPs1Files = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\lib') -Filter '*.ps1' -File)
Check 'PS 侧 lib 那一层不许把 C# 内联回来(名单只住 tools\gdinterop，Add-Type -TypeDefinition 零命中)' (
    (@($libPs1Files).Count -ge 1) -and
    -not (@($libPs1Files | Where-Object {
        (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8) -match 'Add-Type -TypeDefinition' }))) `
    ("lib 扫={0} 本 / 内联={1} 本" -f @($libPs1Files).Count,
     @($libPs1Files | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8) -match 'Add-Type -TypeDefinition' }).Count)
Check '探测还能说清"谁占着前台"，并且读窗口自身状态(最小化/可见/矩形)' (
    $gdWinCs.Length -gt 0 -and $gdWinCs -match 'GetWindowThreadProcessId' -and $gdWinCs -match 'IsWindowVisible' -and
    $gdWinCs -match 'WindowRectText')
# 11-08 刀㉑ 笔(a)：原「件在才跑得动的真调格」臂恒不执行(vision-ark.ps1 已整件退役、Get-GdArkDesktopState 不在现树)，
# 死臂随批摘五格，逐枚点名见提交正文；下面两枚(没复活＋抢前台只动窗口状态)自此是唯一形。
    Check 'PS 端游后端那三枚没在现树复活(找窗口／拍窗口／点窗口)' (
        -not (Get-Command Get-GdArkWindow -ErrorAction SilentlyContinue) -and
        -not (Get-Command Save-GdWindowShot -ErrorAction SilentlyContinue) -and
        -not (Get-Command Send-GdArkClick -ErrorAction SilentlyContinue))
    # 刀㉕ 笔(b)：原「桌面态四格改由 --visiontest 金样接住」的源文本钩子格随批摘除——四串判据不删只换家，真身逐格在 Vision.SelfTest.cs 真跑。
    # $liveStT14 留着：下面那枚问的是 Live.SelfTest.cs 的话术，--livetest 没有「最小化先 SW_RESTORE」的直格，轴不同不跟着批走。
    $liveStT14 = ''
    try { $liveStT14 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'panel-cs\Live.SelfTest.cs') -Raw -Encoding utf8 } catch { }
    # 11-06 刀⑮ 笔(d)-2 复跑红一次照登：首拍把 TryForeground 去问 Live.SelfTest.cs(现读 0 处)，真身在 Live.cs(现读 2 处)＝跨轴；
    # 金样话术那句住在 SelfTest(现读 1 处)，所以两串各归各家，取证轴两本都印出来。
    Check '抢前台那一条在核侧也只动窗口状态(--livetest 钉"全量注入时一个字都不碰窗口调用"，TryForeground 的真身在 Live.cs)' (
        $liveStT14.Length -gt 0 -and $liveStT14.Contains('全量注入时一个字都不碰窗口调用') -and
        $liveCsT13.Contains('TryForeground')) ('Live.cs=' + $liveCsT13.Length + " 字符 / Live.SelfTest.cs=" + $liveStT14.Length + ' 字符')

Write-Host "`n[t15] MAA 自己把队列跑空了，别再傻等 22 分钟(2026-09-25 07:53 那轮现场暴露的)"
# 09-25 07:53 那轮：asst.log 5 次点击全部落地，随后 StartUp@CloseAnno 连认 50 次认不出「锦枫映月」的 ×，6 条链路 0 完成……（细节见该帧）

Write-Host "`n[t16] 只问不点的诊断入口(2026-09-26 加强 AI 干预时加的，全程不联网、不起子进程)"
# 10-28 第二十刀刀③：本节原咬 Add-GdRescueRecord 壳的九格随壳退役，整节改由三处接守——…（细节见该帧）

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
    # 刀⑳ 笔(a)-2 翻形：老形拿未剥注释的 $askSrc 判两枚 PS 函数名，而那两枚已随刀⑮ 笔(d) 出仓，名字只剩史注＝覆盖已丢而格仍绿。
    # 新形只认剥注释的代码面：正锚指真在场的两枚 verb 与话术两格，另加三枚负锚(不许复活那两枚 PS 函数、不许把 scene 写成本地字面量)。
    Check '复用同一套靶子与同一个问价出口(话术由核供给一次，不另写一份提示词，免得两边规则漂移)' (
        $askCode -match 'resolve-rescue-context' -and $askCode -match 'vision-ask-model' -and
        $askCode -match '\[string\]\$ctx\.Scene' -and $askCode -match '\[string\]\$ctx\.UserText' -and
        $askCode -notmatch 'Get-GdVisionTarget' -and $askCode -notmatch 'Invoke-GdVisionRaw' -and
        $askCode -notmatch "scene\s*=\s*'")
    Check '跑完当面告诉人"本文件没有点任何东西"' ($askSrc -match '没有点任何东西')
    Check '问哪一路由清单的 VisionKind 决定，这份文件里没有 ark/mumu 硬对照表' (
        $askSrc -match 'VisionKind' -and $askSrc -notmatch "=\s*'mumu'")
    Check '给了 -Image 就直接用那张图(不截图，也不会因为后端不在就放弃)' ($askSrc -match '\$Image')
    # 11-06 刀⑮ 笔(c)：老形咬 $t.Enabled／$t.AdminWhy／$t.Alive——薄壳自己拿靶子对象的年代。现在三道闸判语全在核内 resolve-rescue-context 腹内
    # (hasBuilder→enabled→isAdmin→hasKey→python→alive)，薄壳只转达 Enabled／NeedsAdmin+AdminWhy／CanAsk；负锚：薄壳不许再自己拼 Alive(alive 那格由 --livetest 盯)。
    Check '开关关着/没提权/对象不在时只说人话，不硬拍(三闸现由 ctx 转达，判语在核内)' (
        $askSrc -match 'ctx\.Enabled' -and $askSrc -match 'AdminWhy' -and $askSrc -match 'ctx\.CanAsk' -and
        $askCode -notmatch 't\.Alive')
} else {
    Check 'tools\vision-ask.ps1 存在(只问不点的诊断入口)' $false '没找到这份文件'
}

$res = Show-GdTestResult -Tag 'ark'
if ($NoExit) { return $res }
exit $(if ($res.Fail) { 1 } else { 0 })
