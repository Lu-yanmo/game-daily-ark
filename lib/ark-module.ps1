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
        Libs             = @('maa.ps1', 'vision-rescue.ps1', 'vision-ark.ps1', 'ark-daily.ps1')
        # 兜底后端的 kind(= New-GdVisionTarget-<kind>)。id 和 kind 不是一回事：1999 的兜底对象是"模拟器屏幕"，
        # kind 叫 mumu 才对得上 adb 那条链。所以这层对照只写在各自清单里，外壳(tools\vision-ask.ps1)只问这一项。
        VisionKind       = 'ark'
        EntryVerbs       = @{
            Merged = @{ Ack = '-AckArk'; ShopDone = '-ArkShopDone'; ShopReset = '-ArkShopReset' }
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
                return (Resolve-GdArkDecision -S $S -Stage $Opt.Stage -Force:([bool]$Opt.Force))
            }
            Preview   = { param($S, $Decision) Show-GdArkPreview -S $S -Decision $Decision }
            Run       = { param($S, $Decision) return (Start-GdArkDaily -S $S -Decision $Decision) }
            Stop      = {
                param($S)
                Stop-MaaAndGame -S $S
                # MAA 的视觉/识别子进程偶尔留在后台，原来在入口的 finally 里无条件杀；
                # 挪进这一路的收尾钩子后，只会在真跑过方舟的轮里执行(更合理，也不会碰不到就报错)
                Get-Process -Name 'MaaAgentBinary' -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch { } }
            }
            Ack       = { param($S) Set-GdArkAck -S $S }
            ShopState = { param($S, $Done) Set-GdArkShopState -S $S -Done:([bool]$Done) }

            # ---- 监督 agent(lib\supervisor.ps1)的可选钩子：给了才监督，重启钩子给了才允许干预。----
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
