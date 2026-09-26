# lib/ark-status.ps1 — 方舟这一路的"体检段落"(status.ps1 只留外壳、编号和共用零件)
#
# 为什么是"每款一组函数 + 外壳按需调用"：拆出去发布的单游戏仓库里，status.ps1 必须只看方舟，
# 又不能靠改行来做到。所以外壳对每段先探一下"这个仓库里有没有这路的函数"，没有就整段跳过。
# 依赖：调用方先点 lib\common.ps1、lib\decisions.ps1、lib\maa.ps1(本文件不重复点，见 lib\decisions.ps1 开头)。

function Get-GdArkEnvRows {
    <# [1] 环境：方舟这边要探的三个路径(标签 -> 路径)，缺失与否由外壳统一染色 #>
    param([Parameter(Mandatory)]$S)
    return [ordered]@{
        'MAA'     = $S.paths.maaDir
        'MAA 配置' = (Join-GdPath $S.paths.maaDir @($S.paths.maaConfig))
        '方舟端游'  = $S.paths.arknightsExe
    }
}

function Show-GdArkStatusVersion {
    param([Parameter(Mandatory)]$S)
    Show-GdVersionFile -Label 'MAA' -Dir $S.paths.maaDir -File $S.paths.maaConfig
}

function Get-GdArkProcNames {
    <# [2] 进程：MAA 和端游客户端。名字就是进程名(不含 .exe)，保持和拆分前一样写死 #>
    return @('MAA', 'Arknights')
}

function Show-GdArkStatusPlan {
    <# [3] 今日判定：方舟那一行。-Offline 传自 status.ps1，用来跳过活动接口的联网 #>
    param([Parameter(Mandatory)]$S, [switch]$Offline)
    $ark = Get-ArkEvent -S $S -Offline:$Offline
    Write-Host "  方舟：$($ark.Mode)  理智刷 $($ark.Stage)  ← $($ark.Reason)" -ForegroundColor $(if ($ark.Mode -eq 'event-pending') { 'Yellow' } else { 'Gray' })
    # 材料补刷一行：只按"今天若跑长草顺不带哪关"报，读三本账不联网。
    # ark-farm.ps1 不在(工程被裁)时整行跳过 —— 和 Resolve-GdArkDecision 的接线守卫同一套路。
    if (Get-Command Resolve-GdArkFarmDecision -ErrorAction SilentlyContinue) {
        try {
            $fp = Resolve-GdArkFarmDecision -S $S -Decision $ark
            Write-Host "  $(Format-GdArkFarmLine -Plan $fp)" -ForegroundColor Gray
        } catch { Write-Host "  材料补刷：没判出来($($_.Exception.Message))" -ForegroundColor DarkGray }
    }
}

function Show-GdArkQueueState {
    <# [4] MAA 队列现状：直接读 configuration.json，不改任何东西 #>
    param([Parameter(Mandatory)]$S)
    $cfgPath = Join-GdPath $S.paths.maaDir @($S.paths.maaConfig)
    # 路径没填时先说清"读不到是因为还没 setup"，别把下面 try 里那句绑定错误当成本工具的毛病
    if (-not (Test-GdPathReady $cfgPath)) { Write-Host "  读不到 MAA 的配置文件：$cfgPath(助手目录还没填 → 先跑 setup.ps1)" -ForegroundColor Yellow; return }
    try {
        $cfg = Read-GdJson -Path $cfgPath
        foreach ($q in @($cfg.Configurations.Default.TaskQueue)) {
            if (-not $q) { continue }
            $plan = if ($q.TaskType -eq 'Fight') { " plan=$(($q.StagePlan | Where-Object { $_ }) -join ',')" } else { '' }
            Write-Host ("  {0,-10} {1,-12} IsEnable={2}{3}" -f $q.TaskType, $q.Name, $q.IsEnable, $plan)
        }
        Write-Host "  RunDirectly(启动即自动开始)= $($cfg.Configurations.Default.Gui.StartUpSettings.RunDirectly)"
        Write-Host "  StartGame(MAA 自己开游戏)  = $($cfg.Configurations.Default.Gui.RuntimeSettings.StartGame)"
        Write-Host "  连接方式 ConnectSettings.Config = $($cfg.Configurations.Default.Gui.ConnectSettings.Config)"
    } catch { Write-Host "  读取失败：$($_.Exception.Message)" -ForegroundColor Red }
}
