# lib/ark-module.ps1 — 《明日方舟》(端游 + MAA) 作为框架模块的清单
#
# 这份文件只做两件事：① 声明这一路的元数据(要不要管理员、要催哪几条路径、提示语里的参数名)；
# ② 把现有函数接成框架那套统一签名的钩子。业务逻辑仍然全在
# lib\maa.ps1 / ark-decisions.ps1 / ark-daily.ps1 / ark-status.ps1 里，这里一个字都没搬 ——
# 所以 test-ark.ps1 那 139 条断言仍然是这一路的回归保护网，本文件不构成第二套实现。
#
# 装载：lib\modules.ps1 的 Import-GdModules 按 lib\*-module.ps1 扫到它并 dot-source，
# 注册进 $global:GdModules。这棵树上没有 lib\maa.ps1 时它虽然会被注册，但
# Get-GdModules -AvailableOnly 会把它筛掉(判据就是助手库在不在)。

Register-GdModule ([pscustomobject]@{
        Id               = 'ark'
        Name             = '明日方舟(端游 + MAA)'
        ShortName        = '方舟'
        AssistantLib     = 'maa.ps1'          # 这一路能不能跑
        OrchestrationLib = 'ark-daily.ps1'    # 有没有入口把这一路当一款游戏在管(合体/单游戏判据)
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
        Libs             = @('maa.ps1', 'vision-rescue.ps1', 'vision-ark.ps1', 'ark-farm.ps1', 'ark-daily.ps1')
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
            Resolve   = {
                param($S, $Opt)
                # -Stage 是方舟专有的"这一轮刷哪几关"；框架只把它塞进 $Opt，不认识它的含义
                # -Farm 同理：材料补刷的"专用轮"开关，含义全在 ark-farm.ps1 / ark-daily.ps1 里
                return (Resolve-GdArkDecision -S $S -Stage $Opt.Stage -Force:([bool]$Opt.Force) -Farm:([bool]$Opt.Farm))
            }
            Preview   = { param($S, $Decision) Show-GdArkPreview -S $S -Decision $Decision }
            Run       = {
                param($S, $Decision)
                $r = Start-GdArkDaily -S $S -Decision $Decision
                # 每轮自证活动图(第 1 刀，2026-10-12)：采集挂在**这里**而不是两条链体各挂一处——
                # 调度器自 10-24 刀③ 起是单臂(只剩换头执行器 Invoke-GdArkDailyRust)，共用这一个入口，
                # 判据只写一遍；写在链体内会让 ark 那两枚 golden 门的调用序多出一枚纯只读记号
                # (Get-GdMaaStageObservation 桩往投影里追加 OBS)，而这一步不改变任何链体行为(它只写
                # state\ark-event-probe.json 给下一轮的判定层)，本就不属门的拍面。
                # 只在这一轮真跑到 MAA 关门前(ok)才采：asst.log 是连日不轮转的大文件，早退/卡死的轮
                # 读到的关名单属于"上一班"——把别人的名单写成今天的结论，等于拿假阳性烧今天的理智。
                # 抛任何错都只 WARN：本轮结论由链体给，自证只是给下一轮留的读数。
                if ([string]$r.Status -eq 'ok') {
                    try {
                        [void](Update-GdArkEventProbe -S $S -Decision $Decision -Obs (Get-GdMaaStageObservation -S $S))
                    } catch { Write-GdLog "活动图自证没做起来：$($_.Exception.Message)(不影响本轮)" -Level WARN }
                }
                return $r
            }
            Stop      = {
                param($S)
                # ⚠ 刀①(2026-11-03)：round 的 stop:ark 已改核内直答(直接问 stop-maa-and-game)，上面那层
                # PS 臂已摘 ⇒ 这一钩子格自此没有 round 消费面，体暂留(1eq.④ 摘臂不摘格)，去留归后续刀。
                # 转接刀·方舟拉起族(11-03)：Stop-MaaAndGame 真身出仓，这一枚钩子与 lib\ark-daily.ps1 的 'stop' 答臂
                # 各自现问同一把核内出口(stop-maa-and-game)。两处不合成一枚 PS 壳是决定：壳回来＝事实源又分家。
                # 完整判语(含 Lines 回放丢档位那笔账)写在 ark-daily.ps1 那一侧，这里不重述。
                $d = Invoke-GdCli -Verb 'stop-maa-and-game' -Body ([pscustomobject]@{})
                foreach ($l in @($d.Lines)) { Write-GdLog ([string]$l) }
                # MAA 的视觉/识别子进程偶尔留在后台，原来在入口的 finally 里无条件杀；
                # 挪进这一路的收尾钩子后，只会在真跑过方舟的轮里执行(更合理，也不会碰不到就报错)
                Get-Process -Name 'MaaAgentBinary' -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch { } }
            }
            Ack       = {
                param($S)
                # 这一格**名字**必须留着：lib\modules.ps1 把 Ack 列在必需钩子名册里(七枚)，删格=装载校验红。
                # 但 2026-10-12 第 1 刀起这条路上没有"活动确认门"了 —— 判定层改读每轮自证
                # (state\ark-event-probe.json)，入口的 -AckArk 参数也已退场，原来的 Set-GdArkAck 一并删除。
                # 所以这里只把话说清楚，不再写 ack 表(写了也没人读)，绝不静默空转。
                # ⚠ 这句提示语里**不许写 -Games ark**：本文件会原样进 ark 单游戏导出仓库，
                # 那边的入口 param() 里没有 -Games(只有 -Force)，玩家照抄就报"找不到参数"——
                # tools\test-lib.ps1 的 [t1d] 门静态扫"入口脚本名 + 参数"就是专抓这一类(2026-10-12 第 1 刀曾红过一次)。
                # 先例见 lib\ark-daily.ps1 那条"退场的开关不写参数名"的口径：共享代码只写两棵树都收的参数。
                Write-GdLog '方舟的「活动确认」门已退场(2026-10-12)：每轮拿活动最后一关当探针自证，进得去就刷活动图，不需要人敲开关；想立刻无视当日结论强刷 = daily-clear.ps1 -Force' -Level WARN
                return $null
            }
            ShopState = { param($S, $Done) Set-GdArkShopState -S $S -Done:([bool]$Done) }

# ---- 监督一族的可选钩子(11-02 刀③ 起答方是 C# 宿主批，旧真身 lib\supervisor.ps1 已出仓)：给了才监督，重启钩子给了才允许干预。----
            SupervisorEvidence = {
                param($S)
                $P = Get-MaaPaths -S $S
                return @{
                    AssistantProc = $P.Name      # MAA 本体进程名
                    AssistantLog  = $P.GuiLog   # 新鲜度按 gui.log(和主流程同一本)
                    GameProc      = [System.IO.Path]::GetFileNameWithoutExtension($S.paths.arknightsExe)
                    DonePattern   = '任务已全部完成'   # 和 Invoke-MaaRun 认的是同一条完成线
                }
            }
            SupervisorRestart = {
                param($S)
                # 拉起方式和主流程逐字相同(Start-Process Exe，MAA 配置里"启动即开队列")，
                # 所以干预的语义 = "当它自己重开了一遍"，风险是多跑，不是乱点。
                $P = Get-MaaPaths -S $S
                Stop-GdProcessTree -Name $P.Name
                Start-Process -FilePath $P.Exe -WorkingDirectory $P.Dir | Out-Null
                return $true
            }

            # ---- status.ps1 那套(只读体检)。这几个是"可选钩子"：清单里没写的段，外壳整段跳过，
            #      等价于拆分前的 Test-GdFunc 'Get-GdArkEnvRows' 探测，只是问题从"函数在不在"
            #      变成了"这一路有没有声明它要出现在体检的哪几段"。----
            StatusRows    = { param($S) Get-GdArkEnvRows -S $S }
            StatusVersion = { param($S) Show-GdArkStatusVersion -S $S }
            StatusProcs   = { param($S) Get-GdArkProcNames }
            StatusPlan    = { param($S, $Offline) Show-GdArkStatusPlan -S $S -Offline:([bool]$Offline) }
            StatusSection = { param($S) Show-GdArkQueueState -S $S }
        }
        # 体检里这一路自己那一节的标题(没有就不写，外壳整段跳过)
        StatusSectionTitle = 'MAA 队列现状'
    })
