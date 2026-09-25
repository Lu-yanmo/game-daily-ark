# lib/maa.ps1 — 配置并驱动 MAA(明日方舟端游 / Win32 控制器)

function Get-MaaPaths {
    param([Parameter(Mandatory)]$S)
    # asst.log 是老配置里可能没有的一项(它只是线索，不是判定依据) → 给个 MAA 默认的相对路径兜底
    $asstRel = if ($S.paths.maaAsstLog) { [string]$S.paths.maaAsstLog } else { 'debug\asst.log' }
    return [pscustomobject]@{
        Dir     = $S.paths.maaDir
        Exe     = (Join-GdPath $S.paths.maaDir @($S.paths.maaExe))
        Config  = (Join-GdPath $S.paths.maaDir @($S.paths.maaConfig))
        GuiLog  = (Join-GdPath $S.paths.maaDir @($S.paths.maaGuiLog))
        AsstLog = (Join-GdPath $S.paths.maaDir @($asstRel))
        Name    = [System.IO.Path]::GetFileNameWithoutExtension($S.paths.maaExe)
    }
}

function Get-MaaAsstStuckState {
    <# 把 asst.log 片段里那四个"当前状态"抠出来：卡在哪个子任务、重试了几次、点击行数、注入行数。
       为什么要单独一个函数：判定要的是数字(重试到第几次才算卡住)，说话要的是句子，两者得用同一份事实。
       注意 inject_input_event **不是**"点击通道活没活"的指标 —— 2026-09-25 早上把整份 asst.log 按动作归类数过：
       全部 2001 次注入都来自同一个子任务 `SwipeToTheLeft`(action=Swipe，基建向左滑那一屏)，
       而 7640 次 ClickSelf / 719 次 ClickRect 一条注入都没有 —— 点击从头到尾都走配置里的发消息方式。
       所以这个计数只说明"这一轮有没有滑过基建"，别拿它推断点得动还是点不动。
       纯字符串处理、不碰文件，方便单独断言。 #>
    param([string]$Text)
    $r = @{ Task = ''; Exec = 0; Clicks = 0; Inject = 0 }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $r }
    foreach ($line in ($Text -split "`r?`n")) {
        # 卡住时整段日志都在同一个任务上循环，所以"最后一次出现的"就是当前值，不用配对
        if ($line -match '"cur_task":"([^"]+)"') { $r.Task = $Matches[1] }
        if ($line -match '"exec_times":(\d+)') { $r.Exec = [int]$Matches[1] }
        if ($line -match 'Win32Controller click:\s*\(') { $r.Clicks++ }
        if ($line -match 'Win32Controller::inject_input_event \| enter') { $r.Inject++ }
    }
    return $r
}

function Get-MaaAsstStuckHint {
    <#
      从 asst.log(MAA 的内核日志，比 gui.log 细几个数量级)里挑出"此刻卡在哪个子任务、重复了多少次、最后点到哪"。
      为什么要单独读它：MAA 卡住时 gui.log 可以整整 22 分钟一个字都不写，asst.log 却一直在刷 ——
      只看 gui.log 的话，能报出来的只有"日志无输出"这种看不出所以然的话。
      2026-09-24 18:00 / 09-25 06:00 两轮都是这样：真凭据在 asst.log 里，StartUp@GameStart 的 exec_times 一路涨到 311，
      每 4 秒往同一个矩形里点一下、模板分数始终 0.99 → 点击全数落空。
      这句话先后被写过两种"原因"，都不成立：一是"splash 上叠了个中秋窗口"(视觉兜底拍到的是登录界面、没有窗口)；
      二是"MAA 抢不到前台退化成 PostMessage 而端游不吃"(数错了我自己：注入只来自基建左滑，点击一直是发消息，
      有人在机器前的成功轮也一样)。所以现在只说被证据撑住的部分：反复点同一处、界面不推进，两种可能都留着。
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $st = Get-MaaAsstStuckState -Text $Text
    $task = $st.Task; $exec = $st.Exec; $click = ''
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match 'Win32Controller click:\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)') { $click = "$($Matches[1]),$($Matches[2])" }
    }
    if (-not $task) { return '' }
    $bits = @("MAA 内核其实还在跑")
    if ($exec -ge 3 -and $click) {
        # 反复点同一处才是"没被吃进去"的特征；只点了一两次不算，别把正常推进中的子任务说成卡住
        $bits += "卡在子任务 $task，已重复 $exec 次(最后点到 $click)"
        $bits += '同一处反复点击而界面不动 → 端游没把这些点击吃进去：要么真有个 MAA 不认识的窗口挡着，要么这一轮窗口不在前台/会话被锁(有人在机器前时，同样的发消息点击是点得动的)'
    } elseif ($exec -ge 3) {
        $bits += "卡在子任务 $task，已重复 $exec 次"
    } else {
        $bits += "最后停在子任务 $task"
    }
    return $bits -join '，'
}

function Set-MaaDailyConfig {
    <#
      按今天的判定结果改写 MAA 的队列开关；写前备份、写后回读校验。
      MAA 必须在运行外部关闭状态才能改(否则退出时会被覆盖)。
    #>
    param([Parameter(Mandatory)]$S, [Parameter(Mandatory)]$Decision, [switch]$Apply)

    $P = Get-MaaPaths -S $S
    if (Test-GdProcessRunning -Name $P.Name) {
        # 真正要写配置时必须先关掉(否则 MAA 退出时会把改动覆盖)；只预览则不影响
        if ($Apply) { throw "MAA 正在运行，请先关闭再改配置" }
        Write-GdLog 'MAA 正在运行：预览不受影响，真正跑时会先接管关闭(残留的高权限 MAA 需要由提权那一轮来收)' -Level WARN
    }
    if (-not (Test-Path -LiteralPath $P.Config)) { throw "MAA 配置不存在：$P.Config" }

    $cfg = Read-GdJson -Path $P.Config
    $root = $cfg.Configurations.Default
    if (-not $root) { throw 'MAA 配置里找不到 Configurations.Default，请检查 MAA 版本/实例名' }

    $changes = @()
    $startup = $root.Gui.StartUpSettings
    if ($startup.RunDirectly -ne $true) {
        if ($Apply) { $startup.RunDirectly = $true }
        $changes += 'StartUpSettings.RunDirectly = true(启动后自动开始)'
    }

    $wantFinish = [string]$S.ark.finishAllSanityWith        # 默认"剩余理智"
    $runtime = $root.Gui.RuntimeSettings
    if ($S.runtime.launchArkFromHelper -and $runtime.StartGame -ne $false) {
        if ($Apply) { $runtime.StartGame = $false }
        $changes += 'RuntimeSettings.StartGame = false(端游改由日常脚本先拉起来，MAA 没存端游路径)'
    }
    $keepOn = @($S.ark.keepQueuesEnabled)
    $turnOff = @($S.ark.disableQueues)
    $stageList = @((([string]$Decision.Stage) -split '[,，、;；\s]+' | Where-Object { $_ }))
    $stageText = $stageList -join ','
    if (-not $stageList.Count) { throw '理智计划为空：检查 settings.ark.defaultStage / planByWeekday' }
    $chk = Test-GdStages -S $S -StageText $stageText
    if ($chk.Bad.Count) {
        if ($Decision.Mode -eq 'idle') { throw "长草计划里的关卡代号不被 MAA 识别：$($chk.Bad -join ', ') → 请改 settings.json 的 ark 计划" }
        Write-GdLog "活动关卡 $($chk.Bad -join ', ') 还不在 MAA 本地关卡表(资源可能没更到)，仍按接口结果写入" -Level WARN
    }
    Write-GdLog "理智计划 $stageText($($chk.Note))"
    $expected = @()

    $queue = @($root.TaskQueue)
    if ($queue.Count -eq 0) { throw 'MAA 配置里的 TaskQueue 为空或结构不认识(预期为数组)' }
    $intent = [ordered]@{}
    foreach ($q in $queue) {
        if (-not $q) { continue }
        $type = [string]$q.TaskType
        $name = [string]$q.Name
        $target = $q.IsEnable

        if ($type -in $turnOff) { $target = $false }
        elseif ($type -eq 'Fight') {
            if (-not $Decision.ClearSanity) { $target = $false }          # 活动未确认 / 只跑非战斗部分
            elseif ($name -eq $wantFinish) { $target = $true }
            elseif ($S.ark.alsoEnableMainFight -and $name -notmatch '剩余') { $target = $true }
            else { $target = $false }
        }
        elseif ($type -in $keepOn) { $target = $true }
        $target = [bool]$target

        if ([bool]$q.IsEnable -ne $target) {
            $changes += "$name → IsEnable=$target"
            if ($Apply) { $q.IsEnable = $target }
        }

        if ($type -eq 'Fight' -and $target) {
            if (@($q.StagePlan) -join ',' -ne $stageText) {
                $changes += "$name → StagePlan = $stageText"
                if ($Apply) { $q.StagePlan = [string[]]$stageList }
            }
            foreach ($flag in @('UseMedicine', 'UseStone', 'UseExpiringMedicine', 'EnableTargetDrop', 'EnableTimesLimit')) {
                if ($q.$flag -ne $false) {
                    $changes += "$name → $flag = false"
                    if ($Apply) { $q.$flag = $false }
                }
            }
        }
        $intent[$name] = $target
        if ($target) { $expected += $type }
    }

    if ($Apply -and $changes.Count -gt 0) {
        $bak = Backup-GdFile -Path $P.Config
        Write-GdJson -Path $P.Config -Object $cfg
        # 回读逐项核对，写盘失败/被 MAA 覆盖时立刻报警
        $verify = Read-GdJson -Path $P.Config
        $bad = @()
        foreach ($q in @($verify.Configurations.Default.TaskQueue)) {
            $n = [string]$q.Name
            if (-not $intent.Contains($n)) { continue }
            if ([bool]$q.IsEnable -ne [bool]$intent[$n]) { $bad += "$n(期望 $($intent[$n])，实际 $($q.IsEnable))" }
        }
        if ($bad.Count) { throw "MAA 配置回读不一致：$($bad -join '; ')(备份：$(Split-Path -Leaf $bak))" }
        Write-GdLog "MAA 配置已更新并校验通过(备份：$(Split-Path -Leaf $bak))" -Level OK
    }
    if ($changes.Count -eq 0) { $changes = @('(无需改动)') }

    return [pscustomobject]@{
        Path = $P.Config
        Changes = $changes
        ExpectedChains = @($expected | Select-Object -Unique)
        Stage = $stageText
        Applied = [bool]$Apply
    }
}

function Invoke-MaaRun {
    <# 启动 MAA → 解析 debug\gui.log 判定完成/停滞/失败 #>
    param(
        [Parameter(Mandatory)]$S,
        [Parameter(Mandatory)][string[]]$ExpectedChains,
        [switch]$DryRun
    )
    $P = Get-MaaPaths -S $S
    if ($DryRun) { Write-GdLog "[dry-run] 将启动 $P.Exe(自动开始队列：$($ExpectedChains -join ', '))" -Level STEP; return @{ Status = 'dryrun'; Detail = '' } }

    $expectedCount = @{}
    foreach ($c in $ExpectedChains) { $expectedCount[$c] = 1 }

    $offset = 0
    if (Test-Path -LiteralPath $P.GuiLog) { $offset = (Get-Item -LiteralPath $P.GuiLog).Length }
    $asstOffset = 0
    $asstHint = ''
    $rescues = @()             # 视觉兜底的每次尝试都记一句，最后拼进结论(见下面的 $detail)
    $rescueLeft = [int]$S.runtime.visionMaxRescue
    if ($rescueLeft -le 0) { $rescueLeft = 2 }     # 一轮最多兜底这么多次，别跟模型没完没了
    if ($P.AsstLog -and (Test-Path -LiteralPath $P.AsstLog)) { $asstOffset = (Get-Item -LiteralPath $P.AsstLog).Length }
    $started = Get-Date
    Write-GdLog "启动 MAA：$($P.Exe)" -Level STEP
    Start-Process -FilePath $P.Exe -WorkingDirectory $P.Dir | Out-Null
    if (-not (Wait-GdCondition -Test { Test-GdProcessRunning -Name $P.Name } -TimeoutSeconds 90 -PollSeconds 3 -What 'MAA 进程启动')) {
        return @{ Status = 'error'; Detail = 'MAA 未能启动(进程未出现)' }
    }
    <# 一开跑就把"这一轮的点击环境长什么样"记进日志：输入桌面 + 端游在不在前台 + 窗口状态。
       为什么要记 —— 无人值守那几轮的失败全是同一个样子(22 分钟无输出、点击全落空)，但日志里没有任何一句话
       能说明当时是"锁屏/窗口不在前台"还是"有个窗口挡着"，事后只能翻 asst.log 猜。这一行当时就把它记下来。
       这棵树上没有探测函数(1999 仓库、自检假环境)就跳过，不影响正常一轮。 #>
    if (Get-Command Get-GdArkDesktopState -ErrorAction SilentlyContinue) {
        try {
            $hwnd = $null
            if (Get-Command Get-GdArkWindow -ErrorAction SilentlyContinue) {
                $gw = Get-GdArkWindow -S $S
                if ($gw) { $hwnd = $gw.Handle }
            }
            $dstProbe = Get-GdArkDesktopState -Hwnd $hwnd
            Write-GdLog "点击环境探测：$($dstProbe.Detail)" $(if ($dstProbe.GameOnFg) { 'INFO' } else { 'WARN' })
        } catch { Write-GdLog "点击环境探测没做起来：$($_.Exception.Message)" -Level WARN }
    }

    $lastGrowth = Get-Date
    $completed = @{}
    $errors = @()
    $chanClicks = 0             # asst.log 里 Win32Controller click 的条数(整轮累计，只是规模参考)
    $stuckTask = ''             # asst.log 最后一次报出来的子任务
    $stuckExec = 0              # 它已经重试到第几次 —— 卡住时这个数会一路涨(实测 311)
    $chanGrabAt = $null         # 判到"点了没动"之后自己抢前台的时刻，抢完再给它 60 秒
    $benignSeen = @{}
    $seen = ''
    $markers = 0                # 认出的标志行数(完成/链路/停滞/异常)：一直是 0 = 日志看不懂了 → unknown-format
    $logChars = 0               # 读到的新增日志字符数：分得清"没写日志"和"写了但不认识"
    $finished = $false          # MAA 自己宣布"任务已全部完成"
    $drained = $false           # MAA 宣布"跑完了但有错误"= 队列已经空了，它不会再自己动(见下面的 $drained 判定)
    $stallWarn = $null
    $timeout = [int]$S.runtime.arkTimeoutMinutes * 60
    $startTimeout = [int]$S.runtime.arkStartTimeoutMinutes * 60
    $stall = [int]$S.runtime.stallTimeoutMinutes * 60
    $idleConfirm = [int]$S.runtime.idleConfirmSeconds
    $arkName = [System.IO.Path]::GetFileNameWithoutExtension($S.paths.arknightsExe)
    $seenGame = [bool](Test-GdProcessRunning -Name $arkName)

    while ($true) {
        Start-Sleep -Seconds 10
        if (-not $seenGame -and (Test-GdProcessRunning -Name $arkName)) {
            $seenGame = $true
            Write-GdLog "端游客户端已被拉起来($arkName)"
        }
        $tail = Get-GdFileTail -Path $P.GuiLog -Offset $offset
        $offset = $tail.Offset
        if ($tail.Text) {
            $lastGrowth = Get-Date
            $seen += $tail.Text
            $lines = @($tail.Text -split "`r?`n")
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if (-not $line.Trim()) { continue }
                $logChars += $line.Length
                if ($line -match '任务已全部完成') {
                    $markers++
                    $finished = $true
                    $used = ''
                    if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match '用时\s*([^)]+)') { $used = $Matches[1].Trim() }
                    Write-GdLog "MAA 宣布任务全部完成$(if ($used) { "(内部计时 $used)" })" -Level OK
                }
                elseif ($line -match 'Completed Task Chain:\s*([A-Za-z]+)') {
                    $markers++
                    $chain = $Matches[1]
                    if (-not $completed.ContainsKey($chain)) { $completed[$chain] = 0 }
                    $completed[$chain]++
                    Write-GdLog "MAA 完成链路：$chain"
                }
                elseif ($line -match '无更新|已停滞') {
                    $markers++
                    $stallWarn = (($line -replace '^.*?<\d+>\s*', '') -replace '\s+', ' ').Trim()
                    Write-GdLog "MAA 停滞告警：$stallWarn" -Level WARN
                }
                elseif ($line -match '任务已完成，但出现错误') {
                    <#
                      MAA 把整条队列跑空了、但过程中有链路报错 —— 它不会自己再跑第二遍。
                      这一句和「任务已全部完成」是两种收尾，早先只认后者，于是这种局要一直等到
                      「asst.log 静默 22 分钟」才反应得过来(2026-09-25 07:53 那轮实测：6 条链路 0 完成，
                      07:56:46 就打出这句，脚本却傻等到 08:19)。认下来，下面立刻处理。
                    #>
                    $markers++
                    $drained = $true
                    Write-GdLog 'MAA 宣布本轮已跑完但有错误(队列已空，它不会再自己动)' -Level WARN
                }
                elseif ($line -match '\[ERR\]|任务失败|Exception|连接失败') {
                    $markers++
                    $msg = ($line -replace '^.*?\]\s*', '') -replace '^\d+\s*', ''
                    # MAA 有几条 ERR 级前缀其实是正常噪音(实测随后链路照样完成)，别混进"异常线索"里
                    $benign = @($S.runtime.benignMaaErrors | Where-Object { $msg -match $_ })
                    if ($msg -and $benign.Count -eq 0) {
                        if ($errors.Count -lt 40) {
                            $errors += $msg.Trim()
                            Write-GdLog "MAA 异常线索：$($msg.Trim())" -Level WARN
                        }
                    } elseif ($msg -and -not $benignSeen.ContainsKey($benign[0])) {
                        $benignSeen[$benign[0]] = $true
                        Write-GdLog "MAA 噪音(已按 benignMaaErrors 忽略)：$($msg.Trim())"
                    }
                }
            }
        }

        <#
          asst.log 每轮也读一次，但**只取线索、不参与"日志有没有在动"的判定**：
          卡住时它照样在刷，拿它去重置 $lastGrowth 的话停滞永远测不出来。
          单次读到的量做个闸：MAA 的内核日志能涨到几十 MB，万一它被原地清空/轮转导致偏移失配，
          宁可跳过这一段，也不要一口气读进内存。
        #>
        try {
            if ($P.AsstLog -and (Test-Path -LiteralPath $P.AsstLog)) {
                $ai = Get-Item -LiteralPath $P.AsstLog
                if (($ai.Length - $asstOffset) -gt 4MB) {
                    $asstOffset = $ai.Length
                } elseif ($ai.Length -gt $asstOffset) {
                    $aTail = Get-GdFileTail -Path $P.AsstLog -Offset $asstOffset
                    $asstOffset = $aTail.Offset
                    if ($aTail.Text) {
                        <# 子任务重试次数才是"点了没动"的直接证据；inject 那个数只反映有没有滑基建，这里不参与判定。 #>
                        $st = Get-MaaAsstStuckState -Text $aTail.Text
                        $chanClicks += $st.Clicks
                        if ($st.Task) { $stuckTask = $st.Task; $stuckExec = $st.Exec }
                        $h = Get-MaaAsstStuckHint -Text $aTail.Text
                        if ($h) { $asstHint = $h }
                    }
                } else {
                    $asstOffset = $ai.Length   # 被原地清空/轮转过：跳到末尾，下一轮只读新增的
                }
            }
        } catch { $asstOffset = 0 }   # 读不动就当没这条线索，绝不影响本轮判定

        $elapsed = ((Get-Date) - $started).TotalSeconds
        $quiet = ((Get-Date) - $lastGrowth).TotalSeconds
        $doneCount = 0
        foreach ($k in $expectedCount.Keys) { $doneCount += [Math]::Min([int]$completed[$k], [int]$expectedCount[$k]) }
        $allDone = ($doneCount -ge $expectedCount.Values.Count) -and ($expectedCount.Count -gt 0)
        $chainText = (($completed.Keys | Sort-Object) -join ', ')
        $detail = "完成链路 $($doneCount)/$($expectedCount.Count)"
        if ($chainText) { $detail += "：$chainText" }
        if ($asstHint) { $detail += "；$asstHint" }
        if ($rescues.Count) { $detail += "；视觉兜底试过 $($rescues.Count) 次，最后一次：$($rescues[-1])" }

        if ($finished) { break }
        if (($markers -eq 0) -and (($elapsed -gt $startTimeout) -or ($quiet -gt $stall))) {
            <# 一条标志都没认出来，却已经过了「该开始」/静默的判定线 → 是看不懂日志，不是跑坏了，别套 not-started/stalled 的猜测 #>
            $why = if ($logChars -eq 0) { "本轮没有读到任何新增日志内容(可能 MAA 换了日志路径或文件名)" }
                   else { "日志在涨(新增 $logChars 字符)但一条认识的标志都没有(可能 MAA 改了文案)" }
            return @{
                Status = 'unknown-format'
                Detail = "MAA $why → 这轮结果不可信，不要按它判定理智是否清完。先看 status.ps1 的 MAA 段，再对着 $($P.GuiLog) 更新 lib\maa.ps1 的判定正则"
                Errors = $errors
            }
        }
        if (-not $seenGame -and $completed.Count -eq 0 -and $elapsed -gt $startTimeout) {
            return @{
                Status = 'not-started'
                Detail = "$([int]$S.runtime.arkStartTimeoutMinutes) 分钟内端游没被拉起、也没有任何链路完成 → 大概率是权限/自动登录/客户端路径问题(MAA 连端游需要管理员)"
                Errors = $errors
            }
        }
        <#
          同一个子任务反复点击、一条链路都没完成 → 别等 22 分钟：无人值守那两轮实测 exec_times 一路涨到 311，
          每 4 秒点一下、界面一步没动，整轮白跑 44 分钟。这里先自己抢一次前台(只动窗口状态、不点客户区)，
          当场把"输入桌面 / 端游在不在前台"记进日志，再给 60 秒；还在原地就早退。
          两个闸各自的作用：`≥60 次`约等于"在同一处点了 4 分钟"，正常推进的子任务到不了这个数；
          `链路 0 完成`保证已经在往前走的轮子绝不在这被掐死。
          别再写"点击退化成 PostMessage"那种话 —— 那是把 inject 数错点得出的错结论(见 Get-MaaAsstStuckState)。
        #>
        if (($stuckExec -ge 60) -and ($completed.Count -eq 0) -and (-not $finished)) {
            if ($null -eq $chanGrabAt) {
                $chanGrabAt = Get-Date
                if (Get-Command Invoke-GdArkForegroundGrab -ErrorAction SilentlyContinue) {
                    try { $grabNote = (Invoke-GdArkForegroundGrab -S $S).Detail }
                    catch { $grabNote = "抢前台抛异常：$($_.Exception.Message)" }
                } else {
                    $grabNote = '这棵树上没有抢前台的函数，只能等停滞判定'
                }
                Write-GdLog "端游没把点击吃进去($stuckTask 已重复 $stuckExec 次、整轮 $chanClicks 次点击)：$grabNote" -Level WARN
            } elseif (((Get-Date) - $chanGrabAt).TotalSeconds -gt 60) {
                return @{
                    Status = 'stalled'
                    Detail = "点击没被端游吃进去：$stuckTask 已重复 $stuckExec 次(整轮 $chanClicks 次点击)且一条链路都没完成，抢前台后 60 秒仍在原地。抢前台时看到的点击环境：$grabNote。$detail"
                    Errors = $errors
                }
            }
        }
        <#
          MAA 宣布"本轮跑完但有错误"= 队列已经空了，它不会再自己动 → 这时候等"静默 22 分钟"是纯白等。
          2026-09-25 07:53 那轮实测：07:56:46 就打出这句、6 条链路 0 完成，脚本却一直等到 08:19 才想起来看屏幕；
          而 08:18 那次兜底真的把挡路窗口关掉之后，老代码只是"清零计时、继续等"，于是又白等到 08:41 才早退。
          那一轮的真相也在屏幕上：中秋活动页「锦枫映月 · 月饼烘焙小教程·第五期」压着主界面，
          MAA 没有这个 × 的模板(StartUp@CloseAnno 连认 50 次认不出)，后面公招/基建/作战/商店/奖励全被它挡住。
          所以这里只做两件被证据撑住的事：**当场兜底一次** + **立刻早退**。
          外层(ark-daily)本来就有一次重试，那次重试会关端游重开 + 重起 MAA —— 今天实测走的就是这条路：
          重开端游之后那张页并没有再弹，重试那一轮 6/6 链路、12 分钟跑完。
          (这里曾写过"只重启 MAA、端游保持登录，免得重试那轮又撞上同一张页"：理由是猜的、那条路也没实测过，已删。
           真碰上"每次登录都弹一次"的活动页，再带着证据把原地重启加回来。)
        #>
        if ($drained -and -not $allDone) {
            if ($rescueLeft -gt 0 -and (Get-Command Invoke-GdVisionRescue -ErrorAction SilentlyContinue)) {
                $rescueLeft--
                $rc = $null
                try { $rc = Invoke-GdVisionRescue -S $S -Tag "drain$($rescues.Count + 1)" }
                catch { $rc = [pscustomobject]@{ Tried = $false; Done = $false; Detail = "兜底抛异常：$($_.Exception.Message)" } }
                $rescues += $rc.Detail
                Write-GdLog "视觉兜底结果：$($rc.Detail)" $(if ($rc.Done) { 'OK' } else { 'WARN' })
            }
            return @{
                Status = 'stalled'
                Detail = "MAA 队列已跑空但只完成 $doneCount/$($expectedCount.Count) 条链路，它不会再自己动 → 不等静默判定，当场兜底过一次就直接早退(外层会重试一次)。$detail"
                Errors = $errors
            }
        }
        if ($stallWarn -and $S.runtime.abortOnMaaStallWarning) {
            return @{ Status = 'stalled'; Detail = "MAA 自身停滞告警(已触发)。$detail"; Errors = @($stallWarn) + $errors }
        }
        if ($elapsed -gt $timeout) {
            return @{ Status = 'timeout'; Detail = "超过 $([int]$S.runtime.arkTimeoutMinutes) 分钟未完成。$detail"; Errors = $errors }
        }
        if ($quiet -gt $stall) {
            <#
              先给视觉兜底一次机会，再判 stalled：MAA 卡在"无限重点一个点不动的按钮"时，
              人眼一看就知道先把挡路弹窗关掉，模板匹配自己永远走不出来(2026-09-24 中秋弹窗那次)。
              没有这个函数(1999 那一侧的仓库、或自检里的假环境)就按原样判停滞。
            #>
            if ($rescueLeft -gt 0 -and (Get-Command Invoke-GdVisionRescue -ErrorAction SilentlyContinue)) {
                $rescueLeft--
                $rc = $null
                try { $rc = Invoke-GdVisionRescue -S $S -Tag "stall$($rescues.Count + 1)" }
                catch { $rc = [pscustomobject]@{ Tried = $false; Done = $false; Detail = "兜底抛异常：$($_.Exception.Message)" } }
                $rescues += $rc.Detail
                Write-GdLog "视觉兜底结果：$($rc.Detail)" $(if ($rc.Done) { 'OK' } else { 'WARN' })
                if ($rc.Done) {
                    $lastGrowth = Get-Date        # 挡路的东西拿掉了，停滞计时从头算，给 MAA 机会继续
                    $stallWarn = $null            # 别让它下一轮又被"停滞告警"提前判死
                    continue
                }
            }
            return @{ Status = 'stalled'; Detail = "MAA 日志 $([int]($quiet/60)) 分钟无输出，判定卡住。$detail"; Errors = $errors }
        }
        if (-not (Test-GdProcessRunning -Name $P.Name)) {
            if ($finished -or $allDone) { break }
            return @{ Status = 'error'; Detail = "MAA 进程提前退出。$detail"; Errors = $errors }
        }
        if ($allDone -and $quiet -gt $idleConfirm) { break }
    }

    $dur = ((Get-Date) - $started).TotalSeconds
    Write-GdLog "MAA 日常链路完成，用时 $([math]::Round($dur/60,1)) 分钟" -Level OK
    return @{ Status = 'ok'; Detail = "完成链路：$(($completed.Keys | Sort-Object) -join ', ')"; Duration = $dur; Errors = $errors }
}

function Start-GdArkClient {
    <#
      MAA 的配置里并没有存端游路径(实测 StartGame=true 也只会报"未找到窗口")，
      所以由日常脚本自己把客户端拉起来，再让 MAA 去连。
    #>
    param([Parameter(Mandatory)]$S, [switch]$DryRun)

    $exe = [string]$S.paths.arknightsExe
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { throw "端游路径不对：$exe(改 settings.paths.arknightsExe)" }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($exe)
    $pattern = if ($S.ark.windowTitlePattern) { [string]$S.ark.windowTitlePattern } else { '明日方舟|Arknights' }

    $win = Get-GdWindowByTitle -Pattern $pattern
    if ($win) { Write-GdLog "端游窗口已存在：[$($win.Name)#$($win.Id)] $($win.Title)"; return $true }

    if (Test-GdProcessRunning -Name $name) {
        Write-GdLog "端游进程在跑但还没有窗口($name)，等它出登录界面" -Level WARN
    } else {
        Write-GdLog "启动端游：$exe" -Level STEP
        if ($DryRun) { Write-GdLog '[dry-run] 跳过实际启动' -Level STEP; return $false }
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
    }

    $haveWindow = Wait-GdCondition -Test { [bool](Get-GdWindowByTitle -Pattern $pattern) } `
        -TimeoutSeconds ([int]$S.runtime.arkWindowTimeoutSeconds) -PollSeconds 5 -What '端游窗口'
    if ($haveWindow) {
        $win = Get-GdWindowByTitle -Pattern $pattern
        Write-GdLog "端游窗口就绪：[$($win.Name)#$($win.Id)] $($win.Title)" -Level OK
        Start-Sleep -Seconds ([int]$S.runtime.arkWarmupSeconds)   # 让它自己登录/进主界面
        return $true
    }
    Write-GdLog "等了 $([int]$S.runtime.arkWindowTimeoutSeconds) 秒还没看到端游窗口(要登录/在更新/路径不对?)" -Level WARN
    return $false
}

function Stop-MaaAndGame {
    param([Parameter(Mandatory)]$S)
    $P = Get-MaaPaths -S $S
    if ($S.runtime.quitAssistantAfter) {
        $n = Stop-GdProcessTree -Name $P.Name
        if ($n) { Write-GdLog "已关闭 MAA($n 个进程)" }
    }
    if ($S.runtime.closeArknightsAfter -and $S.paths.arknightsExe) {
        $n = Stop-GdProcessTree -Name ([System.IO.Path]::GetFileNameWithoutExtension($S.paths.arknightsExe))
        if ($n) { Write-GdLog "已关闭明日方舟端游($n 个进程)" }
    }
}
