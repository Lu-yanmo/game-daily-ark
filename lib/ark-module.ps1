# lib/ark-module.ps1 — 《明日方舟》(端游 + MAA) 作为框架模块的清单
#
# 这份文件只做两件事：① 声明这一路的元数据(要不要管理员、要催哪几条路径、提示语里的参数名)；
# ② 把现有函数接成框架那套统一签名的钩子。业务逻辑仍然全在
# lib\maa.ps1 / ark-decisions.ps1 / ark-daily.ps1 / ark-status.ps1 里，这里一个字都没搬 ——
# 所以 test-ark.ps1 那 139 条断言仍然是这一路的回归保护网，本文件不构成第二套实现。
# ⚠ 改口(11-04 刀④)：上面那句里的 ark-status.ps1 已整件出仓 —— 两枚写死名册(EnvRows/ProcNames)改问核
#   (verb resolve-status-env-rows／resolve-status-proc-names，真身 tools\panel-cs\Detect.cs)，
#   三枚展示壳(StatusVersion/StatusPlan/StatusSection)逐字内联进本文件的钩子(见下面 Status 那段)。
#   「这里一个字都没搬」在那三枚上是破例了一次：搬的是壳的**话术**，判尺与名册都在核里，仍不构成第二套实现。
# ⚠ 改口(11-04 刀⑤)：上面第 ② 件事的射程收窄 —— 判定(Resolve)／预览(Preview)／运行(Run)／收尾(Stop)／
#   门(Ack)／商店(ShopState)／监督(SupervisorEvidence＋SupervisorRestart)八枚块体同日出仓，本清单自此只剩
#   EnvProbes 一枚必需钩子＋status 一族可选钩子。摘它们不是因为语义没了，是因为**消费面没了**：那六族的
#   round 臂已随转接刀·运行面逐枚改成核内直答(gate/stop＝刀①、preview＝刀②、resolve 判定面＝刀③)，
#   监督两枚的完成线规格在 tools\panel-cs\Supervisor.Host.cs 的 SpecOf 里同值另写了一遍、进程树收尾在
#   Round.cs::ProcTree，MaaAgentBinary 杀段在 Chain.cs —— 每一格都先确认"对面在场且可达"才摘，无两头不落。
#   「业务逻辑仍全在 lib\*.ps1」这句自此只对 status 一族成立；Run 钩子里那半段"每轮自证活动图"的语义也不在
#   PS 侧了(核内 round-probe:ark → verb update-ark-event-probe，main.rs 的 daily_round_chain 是它现在唯一的家)。
#   ⚠ EnvProbes 是唯一留下的必需格：它的对面不是函数调用而是**源文本解析**(tools\panel-cs\Panel.Summary.cs
#   的 ProbeSpecs 按一行正则去清单里抠那段)；判语全文在 lib\modules.ps1 末尾那段。
#   旧 Ack 块里那条"退场的开关不写参数名"的约束不靠注释续命：它的尺是 tools\test-lib.ps1 的 [t1d] 门。
#
# 装载：lib\modules.ps1 的 Import-GdModules 按 lib\*-module.ps1 扫到它并 dot-source，
# 注册进 $global:GdModules。这棵树上没有 lib\maa.ps1 时它虽然会被注册，但
# Get-GdModules -AvailableOnly 会把它筛掉(判据就是助手库在不在)。

Register-GdModule ([pscustomobject]@{
        Id               = 'ark'
        Name             = '明日方舟(端游 + MAA)'
        ShortName        = '方舟'
        AssistantLib     = 'maa.ps1'          # 这一路能不能跑(11-04 刀⑦ 笔(a) 起它同时是合体判据那一把尺的唯一读数)
        RequiresAdmin    = $true              # 端游是管理员进程 → MAA 未提权点不动它
        ElevationFlag    = 'arkRequiresElevation'   # settings 里 runtime.<这个键> 显式写 false 才关掉闸门
        # 三句管理员提示里"为什么/否则会怎样"的措辞。框架不许写 MAA、端游这种词，所以话在这里说。
        AdminWhy         = '端游要管理员权限(MAA 未提权时连不上客户端)'
        AdminHint        = 'MAA 可能连不上端游'
        AdminOkNote      = '端游/MAA 需要'
        SettingsBlock    = 'ark'              # $S.ark —— Test-GdShopDoneEnabled 读 shopDoneStopsEvent 用
        PathKeys         = @('maaDir')        # 该催的助手目录(口径要和 Get-GdRequiredPathKeys 一致)
        # 这一路的业务库，由入口在顶层 dot-source(函数里点的会连函数定义一起消失，见 modules.ps1 的 Import-GdModules)。
        # 只写内核不管的那三个：ark-decisions.ps1 归 lib\decisions.ps1 那个门面按文件在不在点，不重复列。
        # vision-rescue.ps1 是两路共用的兜底内核(两份清单都写它，Get-GdModuleLibPaths 按文件名去重、只点一次)；
        # vision-ark.ps1 只有这一路用(PrintWindow 拍端游窗口 + 抢前台真实点击)，即 New-GdVisionTarget-ark 的出处。
        # ark-farm.ps1 是「材料补刷」的判定+记账层(目标清单/掉落学习表/自记账库存)，只有方舟这一路有对等物。
        Libs             = @('maa.ps1', 'vision-rescue.ps1', 'vision-ark.ps1')
        # 11-04 转接刀·运行面刀⑦ 笔(c)：'ark-daily.ps1' 整件出仓，故此处不再列它(不是"漏列"——漏列会被
        # tools\test-modules.ps1 的 -MissingOnly 那格抓成"清单写了而文件不在"，反过来文件没了而名单还写着才是红)。
        # 摘件前置＝岛内函数逐枚的岛外零活调用点现拍(§11.235)；运行面那条腿早换了宿主：daily-clear.ps1 →
        # lib\rust-round.ps1 的 Invoke-GdDailyRoundDispatch → 内置件 gdcore --daily-round，岛里那套 drive 档
        # executor(问-答-重放)在 PS 侧没有调用方 ⇒ 核内 --drive-ark-daily 自此是死出口，那笔账记在"名册枚数"那侧。
        # 文件头那句「业务逻辑仍然全在 …ark-daily.ps1… 里」自此按历史引文读(摘走真身不等于摘走语义，家逐枚点名)：
        # 商店态写盘＋话术在 tools\panel-cs\Round.Data.cs，判定构造段在 Orchestration.cs，拉起/收尾在 Chain.cs，
        # 预览日志面与驱动档链体在 tools\rustcore\src\main.rs——PS 侧不再有一份，"本清单不构成第二套实现"仍成立。
        # 兜底后端的 kind(= New-GdVisionTarget-<kind>)。id 和 kind 不是一回事：1999 的兜底对象是"模拟器屏幕"，
        # kind 叫 mumu 才对得上 adb 那条链。所以这层对照只写在各自清单里，外壳(tools\vision-ask.ps1)只问这一项。
        VisionKind       = 'ark'
        EntryVerbs       = @{
            # Ack 这一格 2026-10-12 起只是**协议占位**：入口的 -AckArk 参数已退场，判定层的提示语也不再生成
            # 「你自己打过之后敲 -AckArk」那句。留着的原因是 Rust 链体那枚 entryverb("ark","Ack") 的 ask 还在
            # 协议名册里(删格=两侧投影变形状=要升契约号)，而它的返回值已经不进任何文案。见 main.rs 同一处注释。
            Merged = @{ Ack = '-AckArk'; ShopDone = '-ArkShopDone'; ShopReset = '-ArkShopReset'; Farm = '-FarmArk' }
        }
        Hooks = [pscustomobject]@{
            # 环境探测清单。条目和标签沿用 daily-clear.ps1 原来写死的那三行，不改措辞：
            # 缺路径时报的那句"缺失：MAA 配置 → …"是玩家见过的，重构不该换掉它。
            EnvProbes = {
                param($S)
                return [ordered]@{
                    'MAA 目录' = $S.paths.maaDir
                    'MAA 配置' = (Join-GdPath $S.paths.maaDir @($S.paths.maaConfig))
                    '方舟端游'  = $S.paths.arknightsExe
                }
            }
            # ---- status.ps1 那套(只读体检)。这几个是"可选钩子"：清单里没写的段，外壳整段跳过，
            #      等价于拆分前那句按"函数在不在"的探测(Test-GdFunc，11-04 刀④ 随 status.ps1 一起退役)，
            #      只是问题从"函数在不在"变成了"这一路有没有声明它要出现在体检的哪几段"。
            #      ⚠ 刀④(2026-11-04)：lib\ark-status.ps1 整件出仓 —— 名册两枚改问核(换答方不换问法：
            #      行集/标签/行序/三态由 verb 逐字作答，染色话术留 status.ps1 壳)；展示三枚内联原函数体。 ----
            StatusRows    = {
                param($S)
                $d = Invoke-GdCli -Verb 'resolve-status-env-rows' -Body ([pscustomobject]@{
                    id = 'ark'; maaDir = $S.paths.maaDir; maaConfig = $S.paths.maaConfig; arknightsExe = $S.paths.arknightsExe
                })
                return @($d.rows)   # 三行 label/shown/state，Show-GdEnvRows 只管染色
            }
            StatusVersion = { param($S) Show-GdVersionFile -Label 'MAA' -Dir $S.paths.maaDir -File $S.paths.maaConfig }
            StatusProcs   = {
                param($S)
                $d = Invoke-GdCli -Verb 'resolve-status-proc-names' -Body ([pscustomobject]@{ id = 'ark' })
                return @($d.names)   # MAA／Arknights：名册住核(Detect.cs)，写死那份自此只有一份
            }
            StatusPlan    = {
                param($S, $Offline)
                $ark = Get-ArkEvent -S $S -Offline:([bool]$Offline)
                Write-Host "  方舟：$($ark.Mode)  理智刷 $($ark.Stage)  ← $($ark.Reason)" -ForegroundColor $(if ($ark.Mode -eq 'event-pending') { 'Yellow' } else { 'Gray' })
                # 材料补刷一行：只按"今天若跑长草顺不带哪关"报，读三本账不联网。
                # ---- 转接刀·运行面刀⑬ 笔(a)(2026-11-06)：判定整段问核(换答方不换问法) ----
                # 三前置/取数/纯判定全在 tools\panel-cs\Chain.cs::ResolveArkFarmDecision，settings.ark 那一路
                # 由核侧自己现读(SettingsOf 缺键即读盘)；这里只把回执压成一行话——"话术单源"由本行独占，
                # 旧 Format-GdArkFarmLine 那句"本轮不追加(…)"的原话照抄，不另立 verb、不改名册枚数。
                # Lines 是核侧本来要 Write-GdLog 的那几句(纠偏说明/今日已认栽)，非专用轮全是默认档 ⇒ 整串按 INFO 回放。
                try {
                    $d = Invoke-GdCli -Verb 'resolve-ark-farm-decision' -Body ([pscustomobject]@{ decision = $ark })
                    foreach ($l in @($d.Lines)) { if ($l) { Write-GdLog ([string]$l) } }
                    if ($d.Farm) { Write-Host "  材料补刷：$($d.Farm.Reason)" -ForegroundColor Gray }
                    else { Write-Host '  材料补刷：本轮不追加(ark.farmTargets 没配、功能关了、或今天不是长草方案)' -ForegroundColor Gray }
                } catch { Write-Host "  材料补刷：没判出来($($_.Exception.Message))" -ForegroundColor DarkGray }
            }
            StatusSection = {
                param($S)
                # 读 configuration.json 与行式的本体在 C#(maa-queue-lines)，这里只有"路径没填→黄字"和"读取失败→红字"两种显示行为。
                $cfgPath = Join-GdPath $S.paths.maaDir @($S.paths.maaConfig)
                # 路径没填时先说清"读不到是因为还没 setup"，别把下面 try 里那句绑定错误当成本工具的毛病
                if (-not (Test-GdPathReady $cfgPath)) { Write-Host "  读不到 MAA 的配置文件：$cfgPath(助手目录还没填 → 先跑 setup.ps1)" -ForegroundColor Yellow; return }
                try {
                    $d = Invoke-GdCli -Verb 'maa-queue-lines' -Body ([pscustomobject]@{ cfgPath = $cfgPath })
                    foreach ($l in @($d.Lines)) { Write-Host $l }
                } catch { Write-Host "  读取失败：$($_.Exception.Message)" -ForegroundColor Red }
            }
        }
        # 体检里这一路自己那一节的标题(没有就不写，外壳整段跳过)
        StatusSectionTitle = 'MAA 队列现状'
    })
