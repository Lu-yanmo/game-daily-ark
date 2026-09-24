# lib/vision-rescue.ps1 — 「卡住了就把画面交给视觉模型」这一路兜底
#
# 为什么要有它：MAA 只认自己模板集里的东西。端游 splash 上叠一个它没见过的新活动弹窗
# (2026-09-24 那个中秋节活动窗口就是)，它会一直在原地点 START —— asst.log 里 exec_times
# 从 1 涨到 316、模板分数始终 0.99， gui.log 却整整 22 分钟一个字不写。
# 人眼一看就知道「先把弹窗关掉」，模板匹配永远看不到这一步 → 这一步交给视觉模型。
#
# 边界(故意收得很紧)：
#   * 只在异常路径被调用(lib\maa.ps1 判到停滞之后)，正常一轮**一个 API 请求都不会发**；
#   * 只让它「关掉挡路的东西」，明确禁止它点领取/前往参与/确定这类会把号往活动里带的按钮；
#   * 一轮最多救 visionMaxRescue 次，每次只点 1 下，点完必须看到画面变了才算数；
#   * 拿不到 key / 没提权 / 截图是黑的 → 说明原因后直接放弃，绝不硬猜。
#
# 权限这条是硬要求：端游 Arknights.exe 的清单是 requireAdministrator，中完整性的进程
# 对它 PostMessage 会返回 false、PrintWindow 也会失败(全都不报错，只是没反应)。
# 计划任务那一路(RunLevel Highest)本来就是提权的，所以定时跑不受影响；
# 手动跑别加 -NoElevate。
#
# 依赖：调用方先点 lib\common.ps1。

$global:GdRescueTypeDef = $false

function Add-GdRescueTypeDef {
    <# 只编译 P/Invoke 签名。Store 版 pwsh 7 里 Add-Type 一旦引用 System.Drawing 的类型就会
       CS0012(找不到 System.Private.Windows.GdiPlus)直接编不过 —— 所以 Bitmap/Graphics 全留在
       PowerShell 侧调，C# 这边只当 user32 的传声筒。 #>
    if ($global:GdRescueTypeDef) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public struct GdRect { public int Left; public int Top; public int Right; public int Bottom; }
public struct GdPoint { public int X; public int Y; }

public static class GdWin
{
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out GdRect r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out GdRect r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref GdPoint p);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out GdPoint p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, IntPtr dwExtraInfo);

    public static GdRect WindowRect(IntPtr h)  { GdRect r; GetWindowRect(h, out r);  return r; }

    // SW_RESTORE：把最小化的窗口放回来。掉线/MAA 收尾都会把端游最小化，那时
    // GetWindowRect 给的是屏幕外那个占位矩形(-32000,-32000，168x29)，拍出来必然是空东西。
    // 这是窗口状态调用，不是客户区输入，所以不会误点游戏里的按钮。
    public static bool Restore(IntPtr h) { return ShowWindow(h, 9); }
    public static GdRect ClientRect(IntPtr h)  { GdRect r; GetClientRect(h, out r);  return r; }

    // 客户区左上角在屏幕上的位置：窗口位图(整窗) → 客户区坐标(PostMessage 要的那个)要靠它换算
    public static GdPoint ClientOrigin(IntPtr h)
    {
        GdPoint p = new GdPoint(); p.X = 0; p.Y = 0;
        ClientToScreen(h, ref p);
        return p;
    }

    public static IntPtr PackClient(int x, int y)
    {
        // LPARAM = MAKELONG(x, y)：低 16 位 x、高 16 位 y(客户区坐标，不是屏幕坐标)
        return (IntPtr)(int)(((uint)(y & 0xFFFF) << 16) | (uint)(x & 0xFFFF));
    }

    public static bool ClickOnce(IntPtr h, int x, int y)
    {
        // WM_NCHITTEST 那套不走，游戏客户端要的是客户区的鼠标消息：MOVE → DOWN(带 MK_LBUTTON) → UP
        PostMessage(h, 0x0200, IntPtr.Zero, PackClient(x, y));          // WM_MOUSEMOVE
        System.Threading.Thread.Sleep(120);
        bool a = PostMessage(h, 0x0201, (IntPtr)0x0001, PackClient(x, y));   // WM_LBUTTONDOWN, wParam=MK_LBUTTON
        System.Threading.Thread.Sleep(90);
        bool b = PostMessage(h, 0x0202, IntPtr.Zero, PackClient(x, y));      // WM_LBUTTONUP
        return a && b;
    }

    // 客户区坐标 → 屏幕坐标(真实鼠标只认屏幕坐标)
    public static GdPoint ToScreen(IntPtr h, int clientX, int clientY)
    {
        GdPoint p = new GdPoint(); p.X = clientX; p.Y = clientY;
        ClientToScreen(h, ref p);
        return p;
    }

    public static GdPoint CursorPos() { GdPoint p; GetCursorPos(out p); return p; }

    public static bool TryForeground(IntPtr h)
    {
        // 后台进程抢前台会被系统拒绝；先"按下 ALT"再抢是公认那招。抢不到就返回 false，
        // 调用方必须改走别的路 —— 真实点击是打在"鼠标当前所在的那个窗口"上的，抢不到前台还点，
        // 就等于在用户正在用的窗口里瞎点一下。
        keybd_event(0x12, 0, 0, IntPtr.Zero);                 // VK_MENU down
        if (IsIconic(h)) { ShowWindow(h, 9); }                 // SW_RESTORE：只在最小化时恢复，别把最大化也撤了
        bool ok = SetForegroundWindow(h);
        keybd_event(0x12, 0, 2, IntPtr.Zero);                 // VK_MENU up(KEYEVENTF_KEYUP)
        System.Threading.Thread.Sleep(350);                    // 等系统真的把焦点换过来
        return ok && (GetForegroundWindow() == h);
    }

    public static bool RealClick(int screenX, int screenY)
    {
        // MAA 在这个端游上走的就是这条：客户端自己渲染鼠标、只认真实输入(见 asst.log 的 inject_input_event)
        if (!SetCursorPos(screenX, screenY)) { return false; } // 目标点在屏幕外/被裁掉了 → 别点
        System.Threading.Thread.Sleep(120);
        mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);             // MOUSEEVENTF_LEFTDOWN
        System.Threading.Thread.Sleep(90);
        mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);             // MOUSEEVENTF_LEFTUP
        return true;
    }
}
'@ -ErrorAction Stop
    $global:GdRescueTypeDef = $true
}

function Get-GdRescueShotDir { Join-Path $global:GD.State 'rescue' }

function Get-GdArkWindow {
    <# 找端游主窗口 → @{Handle;ProcId;Title}；没有返回 $null。用进程名匹配，不用窗口标题
       (标题会随版本变，进程名跟着 paths.arknightsExe 走)。 #>
    param([Parameter(Mandatory)]$S)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($S.paths.arknightsExe)
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.ProcessName -eq $name })) {
        return [pscustomobject]@{ Handle = $p.MainWindowHandle; ProcId = $p.Id; Title = [string]$p.MainWindowTitle }
    }
    return $null
}

function Save-GdWindowShot {
    <# PrintWindow 抓某个窗口的**整窗**位图存成 PNG，顺带把客户区在位图里的偏移一起返回。
       为什么不用截屏(CopyFromScreen)：那条要求窗口在前台、还不能被别的窗口压住，
       无人值守时会把用户正在用的程序一起拍进去(排查时就拍到过用户的浏览器)。
       PrintWindow 是直接把窗口自己画的内容要过来，MAA 用的截屏方式也是它(asst.log 里
       ConnectionInfo 的 method 就是 PrintWindow)，所以这条在这台机器上是被证明可行的。
       返回 @{Ok;Path;ImgW;ImgH;ClientLeft;ClientTop;ClientW;ClientH;AvgLum;Sig;Hash;Why} #>
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$Path
    )
    Add-GdRescueTypeDef
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    if ([GdWin]::IsIconic($Hwnd)) {
        Write-GdLog '端游窗口最小化中 → 先 SW_RESTORE 叫回来再拍' -Level WARN
        [void][GdWin]::Restore($Hwnd)
        Start-Sleep -Milliseconds 1500      # 给它一帧时间重绘，否则拍到的还是空位图
    }
    $wr = [GdWin]::WindowRect($Hwnd)
    $w = $wr.Right - $wr.Left; $h = $wr.Bottom - $wr.Top
    if ($w -lt 200 -or $h -lt 150) {
        # 分开报：还是 168x29 就是"恢复没成功/又被最小化了"，别让人以为是窗口真坏了
        $why = if ([GdWin]::IsIconic($Hwnd)) { "端游窗口仍最小化(拍不到东西) ${w}x${h}" } else { "窗口尺寸异常 ${w}x${h}" }
        return [pscustomobject]@{ Ok = $false; Why = $why }
    }
    $bmp = $null; $g = $null
    try {
        $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc()
        # 2 = PW_RENDERFULLCONTENT：Win10 之后带 DirectComposition/硬件加速的窗口不加这个会拍成黑屏
        $ok = [GdWin]::PrintWindow($Hwnd, $hdc, 2)
        if (-not $ok) { $ok = [GdWin]::PrintWindow($Hwnd, $hdc, 0) }   # 老一点的窗口过程只认 0，再试一次
        $g.ReleaseHdc($hdc)
        if (-not $ok) { return [pscustomobject]@{ Ok = $false; Why = 'PrintWindow 返回 false(权限不够或窗口已关闭)' } }
        # 平均亮度：整屏黑的时候模型会一本正经地胡说八道，白花一次钱，所以在这里就拦掉。
        # 顺带算一张 16x9 的"粗亮度签名"：判"点完画面到底变没变"用它 —— 文件哈希不行，
        # 端游背景有噪点动画，同一画面两次截图哈希都不一样(2026-09-24 就是这么误判过一次"救活了")。
        $sum = 0L; $n = 0
        $acc = New-Object 'int[]' 144; $cnt = New-Object 'int[]' 144
        for ($y = 0; $y -lt $h; $y += 7) {
            for ($x = 0; $x -lt $w; $x += 7) {
                $c = $bmp.GetPixel($x, $y)
                $l = [int](($c.R * 30 + $c.G * 59 + $c.B * 11) / 100)
                $sum += $l; $n++
                $gy = [int]($y / $h * 16); if ($gy -gt 15) { $gy = 15 }
                $gx = [int]($x / $w * 9);  if ($gx -gt 8)  { $gx = 8 }
                $k = $gy * 9 + $gx
                $acc[$k] += $l; $cnt[$k]++
            }
        }
        $lum = [math]::Round($sum / [math]::Max(1, $n))
        # /8 量化：把抗锯齿和噪点造成的 1~2 档抖动压掉，剩下的才是"这块区域真的换了内容"
        $sig = for ($k = 0; $k -lt 144; $k++) { if ($cnt[$k]) { [int][math]::Round($acc[$k] / $cnt[$k] / 8) } else { 0 } }
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $co = [GdWin]::ClientOrigin($Hwnd)
        $cr = [GdWin]::ClientRect($Hwnd)
        return [pscustomobject]@{
            Ok = $true; Path = $Path; ImgW = $w; ImgH = $h
            ClientLeft = $co.X - $wr.Left; ClientTop = $co.Y - $wr.Top
            ClientW = $cr.Right; ClientH = $cr.Bottom
            AvgLum = $lum; Sig = ($sig -join ','); Hash = (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash; Why = ''
        }
    } catch {
        return [pscustomobject]@{ Ok = $false; Why = "截图失败：$($_.Exception.Message)" }
    } finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
    }
}

function Get-GdVisionSystemPrompt {
    <# 提示词单独成一个函数：这样自检能直接断言"禁止点领取"这类关键约束还在，
       而不是改一句话把安全边界改没了都没人发现。 #>
    return @'
你是明日方舟端游自动化流程里的"看屏幕的人"。自动化助手(MAA)不认识界面上没收录过的弹窗，有时会一直在原地
点同一个按钮。给你一张端游窗口截图，请判断画面上有没有挡住主流程的弹窗，并指出该点哪里把它关掉。

只输出一个 JSON 对象，不要 markdown 代码块、不要任何解释文字：
{"blocking": true 或 false, "what": "不超过20字，说明挡住的是什么", "clicks": [{"x": 整数, "y": 整数, "why": "不超过14字"}]}

必须遵守的规则：
1. x、y 是相对这张图片宽、高的千分比(0-1000)，不是像素。换算：像素x = x/1000*图片宽。
2. clicks 最多 1 个。只允许给"关闭/取消/暂不/跳过/知道了/X"这类**只会把弹窗关掉**的位置。
3. 绝对不要给"领取""前往参与""确定""开始行动""充值"这类会推进游戏状态的按钮，即使它在画面正中。
4. 关闭按钮通常在该弹窗的右上角(常常是一个 X 或小圆圈)。弹窗有多个关闭位时，选最靠右上角的那个。
5. 画面上没有挡住流程的弹窗 → blocking 给 false、clicks 给空数组。拿不准也一律给空数组。
6. 不要输出坐标以外的多余字段。
'@
}

function Get-GdVisionVerdictFromText {
    <# 把模型回复解析成 @{Blocking;What;X;Y;Why}，解析不出来返回 $null。
       模型偶尔会裹一层 ```json 或前后带一句话，所以从整段文本里"抠"第一个 JSON 对象，
       而不是假设整段就是 JSON。纯字符串处理，自检直接喂样本。 #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text -replace '```[a-zA-Z]*', ''
    $start = $t.IndexOf('{')
    if ($start -lt 0) { return $null }
    $depth = 0; $json = ''
    for ($i = $start; $i -lt $t.Length; $i++) {
        $ch = $t[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth-- }
        if ($depth -lt 0) { break }
        $json += $ch                                  # 收尾那个 } 也要留着，否则抠出来的是半个 JSON
        if ($depth -eq 0 -and $i -gt $start) { break }
    }
    if (-not $json) { return $null }
    try { $o = $json | ConvertFrom-Json } catch { return $null }
    $clicks = @($o.clicks)
    [pscustomobject]@{
        Blocking = [bool]$o.blocking
        What     = [string]$o.what
        X        = if ($clicks.Count -ge 1) { $clicks[0].x } else { $null }
        Y        = if ($clicks.Count -ge 1) { $clicks[0].y } else { $null }
        Why      = if ($clicks.Count -ge 1) { [string]$clicks[0].why } else { '' }
    }
}

function Get-GdRescueClickPoint {
    <# 模型 verdict(千分比，相对整窗位图) → PostMessage 要的**客户区**坐标。
       窗口位图里有标题栏和边框，所以要先减掉客户区在位图里的原点，再按客户区尺寸裁住边界。
       越界(说明模型指到窗口外/标题栏上，或者它压根没给坐标)返回 $null → 宁可这一轮不救。 #>
    param(
        [Parameter(Mandatory)]$Shot,
        [Parameter(Mandatory)]$Verdict,
        [int]$Max = 1000
    )
    if ($null -eq $Verdict.X -or $null -eq $Verdict.Y) { return $null }
    $nx = 0; $ny = 0
    if (-not ([int]::TryParse([string]$Verdict.X, [ref]$nx) -and [int]::TryParse([string]$Verdict.Y, [ref]$ny))) { return $null }
    if ($nx -lt 0 -or $nx -gt $Max -or $ny -lt 0 -or $ny -gt $Max) { return $null }
    $px = [int][math]::Round($nx / $Max * $Shot.ImgW)     # 位图里的像素
    $py = [int][math]::Round($ny / $Max * $Shot.ImgH)
    $cx = $px - [int]$Shot.ClientLeft                     # 客户区坐标
    $cy = $py - [int]$Shot.ClientTop
    if ($cx -lt 0 -or $cy -lt 0) { return $null }
    if ($cx -ge [int]$Shot.ClientW -or $cy -ge [int]$Shot.ClientH) { return $null }
    return [pscustomobject]@{ ClientX = $cx; ClientY = $cy; BitmapX = $px; BitmapY = $py; NormX = $nx; NormY = $ny }
}

function New-GdRescueSkip {
    <# "这次没救成，原因是……"的统一出口：Tried=$false 表示连一次点击都没发出去 #>
    param([string]$Why)
    return [pscustomobject]@{ Tried = $false; Done = $false; Detail = $Why }
}

function Get-GdVisionApiKey {
    <# 环境变量优先(便于不落盘)，其次 settings.runtime.visionApiKey。
       key 只读不打印：日志里永远只出现"有没有配"，不出现内容。 #>
    param([Parameter(Mandatory)]$S)
    $k = $env:DASHSCOPE_API_KEY
    if (-not $k -and $S.runtime -and $S.runtime.visionApiKey) { $k = [string]$S.runtime.visionApiKey }
    if ($k) { return $k.Trim() }
    return ''
}

function Resolve-GdVisionEndpoint {
    <# 从控制台复制下来的往往是"基础地址"(以 /v1 或 /compatible-mode/v1 结尾)，而 POST 要打到
       .../chat/completions。两种写法都给同一个结果，已经带全的原样返回 —— 免得玩家对着 README
       里那个默认值发愣：他自己的地址末尾少了 /chat/completions 就会 404，而这看起来像"模型不可用"。 #>
    param([string]$Base)
    $b = if ($Base) { ([string]$Base).Trim().TrimEnd('/') } else { '' }
    if (-not $b) { $b = 'https://dashscope.aliyuncs.com/compatible-mode/v1' }
    if ($b -match '(?i)/chat/completions$') { return $b }
    return "$b/chat/completions"
}

function Invoke-GdVisionAsk {
    <# 一次真实的视觉模型调用：图片走 data:image/png;base64 内联(百炼兼容 OpenAI 的接口收这个)，
       返回解析后的 verdict；任何一步不对都 throw，由调用方统一降级成"这轮不救"。
       单独成函数就是为了给自检一个可以整体替换的假实现(自检绝不联网)。 #>
    param(
        [Parameter(Mandatory)]$S,
        [Parameter(Mandatory)][string]$ImagePath
    )
    $key = Get-GdVisionApiKey -S $S
    if (-not $key) { throw '没有视觉模型的 API key(settings.runtime.visionApiKey 或环境变量 DASHSCOPE_API_KEY)' }
    Enable-GdTls12
    $model = if ($S.runtime.visionModel) { [string]$S.runtime.visionModel } else { 'qwen3.8-flash' }
    $url   = Resolve-GdVisionEndpoint -Base ([string]$S.runtime.visionBaseUrl)
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($ImagePath))
    $body = @{
        model          = $model
        temperature    = 0
        max_tokens     = 300
        response_format = @{ type = 'json_object' }
        messages       = @(
            @{ role = 'system'; content = (Get-GdVisionSystemPrompt) },
            @{ role = 'user'; content = @(
                @{ type = 'image_url'; image_url = @{ url = "data:image/png;base64,$b64" } },
                @{ type = 'text'; text = '这是端游当前画面。按规则只回一个 JSON 对象。' }
            ) }
        )
    } | ConvertTo-Json -Depth 8 -Compress
    $sec = [int]$S.runtime.visionTimeoutSeconds
    if ($sec -le 0) { $sec = 45 }
    $resp = Invoke-RestMethod -Uri $url -Method Post -TimeoutSec $sec `
        -Headers @{ Authorization = "Bearer $key" } `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
    $text = ''
    if ($resp.choices -and @($resp.choices).Count -ge 1) { $text = [string]@($resp.choices)[0].message.content }
    return (Get-GdVisionVerdictFromText -Text $text)
}

function Test-GdShotChanged {
    <# 点完到底有没有真变：比两张图的 16x9 粗亮度签名，数"变了多少格"。
       阈值(≥2 格、每格 ≥3 档)是按端游实测噪声定的：噪点动画顶多让个别格子抖 1~2 档，
       而"关掉一个弹窗"必然动到一整片区域。纯字符串处理 → 自检能直接喂样本，不用真截图。 #>
    param(
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)]$After,
        [int]$MinCells = 2,
        [int]$MinDelta = 3
    )
    if (-not $Before.Sig -or -not $After.Sig) {
        return [pscustomobject]@{ Known = $false; Changed = $false; Cells = -1; Detail = '没有画面签名可比对(截图那一步就没成)' }
    }
    $a = @($Before.Sig -split ',' | ForEach-Object { [int]$_ })
    $b = @($After.Sig  -split ',' | ForEach-Object { [int]$_ })
    if ($a.Count -ne $b.Count) {
        return [pscustomobject]@{ Known = $false; Changed = $false; Cells = -1; Detail = "两次画面尺寸不同($($a.Count) 格 vs $($b.Count) 格)" }
    }
    $diff = 0
    for ($i = 0; $i -lt $a.Count; $i++) { if ([math]::Abs($a[$i] - $b[$i]) -ge $MinDelta) { $diff++ } }
    return [pscustomobject]@{ Known = $true; Changed = ($diff -ge $MinCells); Cells = $diff
        Detail = "画面变了 $diff 格(判据：≥$MinCells 格、每格 ≥$MinDelta 档)" }
}

function Send-GdArkClick {
    <# 往端游客户区某个点发一次左键，返回 @{Mode;Sent}。
       为什么不再只靠 PostMessage：2026-09-24 实测过 —— 消息确实发出去了、坐标也正好压在
       "是否消耗1次联络机会"那个 × 上(模型给的点位偏差只有 2 像素)，弹窗却纹丝不动；
       而 MAA 在这个端游上走的是真实鼠标(asst.log 里的 inject_input_event，gui.log 那句
       "PC 端鼠标为独立渲染"也是这个意思)。所以默认抢前台 + 真实点击；
       抢不到前台才退回 PostMessage —— 宁可点不动，也不能把真实点击漏进用户正在用的窗口。 #>
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$ClientX,
        [Parameter(Mandatory)][int]$ClientY
    )
    Add-GdRescueTypeDef
    $pt = [GdWin]::ToScreen($Hwnd, $ClientX, $ClientY)
    if ([GdWin]::TryForeground($Hwnd)) {
        $old = [GdWin]::CursorPos()
        $sent = [GdWin]::RealClick($pt.X, $pt.Y)
        Start-Sleep -Milliseconds 200
        [void][GdWin]::SetCursorPos([int]$old.X, [int]$old.Y)   # 鼠标放回原处，别留在游戏窗口里
        if ($sent) { return [pscustomobject]@{ Mode = '真实点击'; Sent = $true } }
    }
    return [pscustomobject]@{ Mode = 'PostMessage(没抢到前台，很可能点不动)'; Sent = [GdWin]::ClickOnce($Hwnd, $ClientX, $ClientY) }
}

function Invoke-GdVisionRescue {
    <# 兜底总入口：截图 → 问模型 → 点一下 → 再截图确认画面真的变了。
       返回 @{Tried;Done;Detail}。Tried=是否真的动过手；Done=是否点完并且画面确实变了。
       一切前置条件不满足都返回 Tried=$false + 一句人话，调用方只管把 Detail 拼进结论里。 #>
    param(
        [Parameter(Mandatory)]$S,
        [string]$Tag = 'stall'
    )
    if ($S.runtime.arkVisionRescue -eq $false) { return (New-GdRescueSkip 'arkVisionRescue=false，视觉兜底已关闭') }
    if (-not (Test-GdAdmin)) {
        return (New-GdRescueSkip '当前不是管理员权限：端游是 requireAdministrator，这个权限下点它不会有任何反应，跳过兜底')
    }
    if (-not (Get-GdVisionApiKey -S $S)) {
        return (New-GdRescueSkip '没配视觉模型 key(见 settings 里的 runtime.visionApiKey)，本轮不尝试兜底')
    }
    $ark = Get-GdArkWindow -S $S
    if (-not $ark) { return (New-GdRescueSkip '端游窗口已经不在了，兜底没有对象') }

    $dir = Get-GdRescueShotDir
    $stamp = Get-Date -Format 'MMdd-HHmmss'
    $before = Save-GdWindowShot -Hwnd $ark.Handle -Path (Join-Path $dir "ark-$Tag-$stamp-before.png")
    if (-not $before.Ok) { return (New-GdRescueSkip "截图失败：$($before.Why)") }
    if ([int]$before.AvgLum -lt 8) {
        return (New-GdRescueSkip "截图几乎是全黑(平均亮度 $($before.AvgLum))：桌面可能锁了或窗口没在渲染，问模型只会白花钱")
    }
    Write-GdLog "视觉兜底：已拍端游窗口($($before.ImgW)x$($before.ImgH)，亮度 $($before.AvgLum))，交给模型判断" -Level WARN
    $v = $null
    try { $v = Invoke-GdVisionAsk -S $S -ImagePath $before.Path }
    catch { return (New-GdRescueSkip "模型调用失败：$($_.Exception.Message)") }
    if (-not $v) { return (New-GdRescueSkip '模型没按格式回 JSON，不拿它的话当依据') }
    if (-not $v.Blocking) { return (New-GdRescueSkip "模型认为没有弹窗挡路($($v.What))") }
    $pt = Get-GdRescueClickPoint -Shot $before -Verdict $v
    if (-not $pt) {
        return (New-GdRescueSkip "模型说挡路的是$($v.What)，但它给的坐标($($v.X),$($v.Y))落不到客户区里 → 不点")
    }
    Write-GdLog "视觉兜底：$($v.What) → 点客户区 $($pt.ClientX),$($pt.ClientY)($($v.Why))" -Level WARN
    $click = Send-GdArkClick -Hwnd $ark.Handle -ClientX ([int]$pt.ClientX) -ClientY ([int]$pt.ClientY)
    Start-Sleep -Seconds 6
    $after = Save-GdWindowShot -Hwnd $ark.Handle -Path (Join-Path $dir "ark-$Tag-$stamp-after.png")
    Clear-GdRescueShotDir
    if (-not $after.Ok) { return (New-GdRescueSkip "点完补拍失败：$($after.Why)($($click.Mode))，无法确认是否生效") }
    $chg = Test-GdShotChanged -Before $before -After $after
    if (-not $chg.Known) {
        return [pscustomobject]@{ Tried = $true; Done = $false;
            Detail = "$($click.Mode)已经发过(点位 $($pt.ClientX),$($pt.ClientY))，但$($chg.Detail) → 不算救活" }
    }
    if (-not $chg.Changed) {
        return [pscustomobject]@{ Tried = $true; Done = $false;
            Detail = "按模型说的把$([string]$v.What)点了一下($($click.Mode)，点位 $($pt.ClientX),$($pt.ClientY))，$($chg.Detail) → 弹窗还在，这一路走不通" }
    }
    return [pscustomobject]@{ Tried = $true; Done = $true;
        Detail = "已按模型判断关掉$([string]$v.What)($($click.Mode) 点位 $($pt.ClientX),$($pt.ClientY))，$($chg.Detail)" }
}

function Clear-GdRescueShotDir {
    <# 兜底截图是取证用的，别把 state\rescue 堆成几百张：按时间留最近 24 张(= 12 次兜底)。 #>
    $dir = Get-GdRescueShotDir
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $keep = @(Get-ChildItem -LiteralPath $dir -Filter '*.png' -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -Skip 24)
    foreach ($f in $keep) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
}
