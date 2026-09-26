# lib/vision-ark.ps1 — 视觉兜底的**端游后端**：PrintWindow 拍窗口 + 抢前台真实点击
#
# 这份文件从 lib\vision-rescue.ps1 里拆出来(2026-09-26)，原因是那一份现在两路共用，
# 不能再引用 paths.arknightsExe、也不能假设"点东西要先提权"。端游这一路的特殊性全在这里：
#   * 截图靠 PrintWindow(不是 CopyFromScreen)，窗口位图里有标题栏和边框，坐标要换客户区；
#   * 点击靠"抢前台 + 真实鼠标"，抢不到才退回 PostMessage；
#   * 端游 Arknights.exe 的清单是 requireAdministrator —— 中完整性的进程对它 PostMessage 返回 false、
#     PrintWindow 也会失败(全都不报错，只是没反应)。所以这一路的靶子 NeedsAdmin=$true，
#     计划任务那一路(RunLevel Highest)本来就有提权，定时跑不受影响；手动跑别加 -NoElevate。
#
# 契约(Enabled/Why/Shot/Click/Alive 各是什么形状)写在 lib\vision-rescue.ps1 的文件头。
#
# 依赖：调用方先点 lib\common.ps1 与 lib\vision-rescue.ps1(后者提供 Get-GdShotStats)。

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
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out GdPoint p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, IntPtr dwExtraInfo);
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr OpenInputDesktop(uint dwFlags, bool fInherit, uint dwDesktopAccess);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool GetUserObjectInformationW(IntPtr hObj, int nIndex, System.Text.StringBuilder pvInfo, uint nLength, out uint lpnLengthNeeded);
    [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr hDesktop);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint lpdwProcessId);

    public static GdRect WindowRect(IntPtr h)  { GdRect r; GetWindowRect(h, out r);  return r; }

    // 下面三个都是"看一眼现场"的只读调用，给点击环境探测用：不动窗口、不点客户区、不动鼠标。
    public static bool Visible(IntPtr h) { return IsWindowVisible(h); }
    public static string CursorText()
    {
        GdPoint p;
        if (!GetCursorPos(out p)) { return ""; }
        return p.X + "," + p.Y;
    }
    public static string WindowRectText(IntPtr h)
    {
        GdRect r;
        if (!GetWindowRect(h, out r)) { return ""; }
        return r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top);
    }

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

    // 当前"接收鼠标键盘的那个桌面"叫什么：解锁时是 Default，锁屏/切到登录界面时是 Winlogon。
    // 为什么读它：这是"真实点击到底进不进得来"最直接的判据，而且不需要管理员。
    // OpenInputDesktop 只要 DESKTOP_READOBJECTS(0x0002)，UOI_NAME 是 2。拿不到名字返回空串(调用方按"不知道"处理)。
    public static string InputDesktopName()
    {
        IntPtr h = OpenInputDesktop(0x0002, false, 0x0002);
        if (h == IntPtr.Zero) { return ""; }
        try
        {
            System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
            uint need = 0;
            if (!GetUserObjectInformationW(h, 2, sb, 512, out need)) { return ""; }
            return sb.ToString();
        }
        finally { CloseDesktop(h); }
    }

    public static IntPtr ForegroundWindow() { return GetForegroundWindow(); }

    public static uint WindowPid(IntPtr h) { uint pid; GetWindowThreadProcessId(h, out pid); return pid; }

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
        // 真实鼠标：光标移过去再按下/抬起，我们自己的兜底点击走这条。
        // 注意别再把它说成"MAA 在这个端游上也是这么点的"：2026-09-25 把整份 asst.log 按动作归类数过，
        // inject_input_event 全部来自基建左滑(SwipeToTheLeft)，7600 多次点击一条注入都没有 —— MAA 的点击
        // 一直是配置里的发消息方式，而那种点击在有人在机器前时是点得动这个端游的。
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

function Get-GdArkDesktopState {
    <# 一句话回答"这一轮的点击环境长什么样"：输入桌面叫什么 + 端游窗口在不在前台 + 谁占着前台 + 窗口本身的状态。
       为什么要记它：无人值守那几轮(06:00)失败得一模一样 —— MAA 每 4 秒往 splash 的 START 点一下、点了 311 下、
       模板分始终 0.99、界面一步不动，而日志里没有当时"鼠标键盘到底进不进得来"的任何记录，事后只能猜。
       被否掉的猜测有两个：一是"有个弹窗挡着"(视觉兜底当场拍到的是登录界面、没有窗口)；
       二是"MAA 抢不到前台退化成 PostMessage 而端游不吃"(inject_input_event 其实全部来自基建左滑，
       点击在成功轮里也一直是发消息 —— 见 lib\maa.ps1 的 Get-MaaAsstStuckState)。
       剩下能分辨的就只有现场状态，所以把它一次记全：桌面名 / 前台归属 / 最小化 / 可见 / 窗口矩形 / 光标位置。
       纯读，不动任何窗口，也不联网。 #>
    param($Hwnd)
    Add-GdRescueTypeDef
    $desk = [string]([GdWin]::InputDesktopName())
    $fg = [GdWin]::ForegroundWindow()
    $onFg = ($Hwnd -and ($fg -ne [IntPtr]::Zero) -and ($fg -eq [IntPtr]$Hwnd))
    $fgName = ''
    try {
        $fgPid = [uint32][GdWin]::WindowPid($fg)
        if ($fgPid -gt 0) { $fgName = [string]((Get-Process -Id $fgPid -ErrorAction SilentlyContinue).ProcessName) }
    } catch { $fgName = '' }
    # 桌面名字读不到时按"不知道"处理，别把它说成"锁屏了"——OpenInputDesktop 在个别环境会被安全策略挡
    $locked = if ($desk) { ($desk -ne 'Default') } else { $null }
    $bits = @()
    if (-not $desk) { $bits += '输入桌面=读不到(无法判断是否锁屏)' }
    elseif ($locked) { $bits += "输入桌面=$desk(会话不在正常桌面，鼠标键盘进不来)" }
    else { $bits += '输入桌面=Default(未锁屏)' }

    if (-not $Hwnd) {
        $bits += '端游窗口没找到'
    } else {
        if ($onFg) { $bits += '端游在前台=是' }
        else {
            $who = if ($fgName) { $fgName } else { '未知窗口' }
            $bits += "端游在前台=否(前台是 $who)"
        }
        # 窗口自己这一侧的状态：锁屏时这几项往往还是"可见 + 正常矩形"，所以它是用来**排除**"窗口没了/最小化了"的
        $st = @()
        if ([GdWin]::IsIconic([IntPtr]$Hwnd)) { $st += '最小化' }
        if (-not [GdWin]::Visible([IntPtr]$Hwnd)) { $st += '不可见' }
        $rc = [string]([GdWin]::WindowRectText([IntPtr]$Hwnd))
        if ($rc) { $st += $rc }
        if ($st.Count) { $bits += "端游窗口状态=" + ($st -join '/') }
    }
    $cur = [string]([GdWin]::CursorText())
    if ($cur) { $bits += "光标在 $cur" }

    return [pscustomobject]@{
        Desktop    = $desk
        Locked     = $locked
        GameOnFg   = [bool]$onFg
        FgProcess  = $fgName
        Cursor     = $cur
        Detail     = $bits -join '；'
    }
}

function Invoke-GdArkForegroundGrab {
    <# 把端游窗口抢回前台(ALT hack)，只动窗口状态、不点客户区，所以不会误点游戏里的按钮。
       抢不到就照实返回 false —— 调用方要么改走别的路，要么明确说"这一轮点不动"，别硬点。
       成功与否都把现场状态带回 Detail：这一轮之后要不要早退，靠的就是这几个字。 #>
    param([Parameter(Mandatory)]$S)
    Add-GdRescueTypeDef
    $w = Get-GdArkWindow -S $S
    if (-not $w) { return @{ Ok = $false; Detail = '端游窗口没找到，抢前台无从谈起' } }
    $ok = [GdWin]::TryForeground($w.Handle)
    $st = Get-GdArkDesktopState -Hwnd $w.Handle
    if ($ok) { $detail = "已把端游窗口抢到前台($($w.Title)) —— $($st.Detail)" }
    else { $detail = "抢前台没成功 —— $($st.Detail)" }
    return @{ Ok = [bool]$ok; Handle = $w.Handle; Detail = $detail }
}

function Save-GdWindowShot {
    <# PrintWindow 抓某个窗口的**整窗**位图存成 PNG，顺带把客户区在位图里的偏移一起返回。
       为什么不用截屏(CopyFromScreen)：那条要求窗口在前台、还不能被别的窗口压住，
       无人值守时会把用户正在用的程序一起拍进去(排查时就拍到过用户的浏览器)，
       被全屏游戏挡住时拍到的还是游戏本身(见记忆 printwindow-beats-copyfromscreen)。
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
        # 亮度与"点完变没变"的签名两路共用一把尺子，算法在 lib\vision-rescue.ps1 的 Get-GdShotStats
        $stats = Get-GdShotStats -Bmp $bmp -W $w -H $h
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $co = [GdWin]::ClientOrigin($Hwnd)
        $cr = [GdWin]::ClientRect($Hwnd)
        return [pscustomobject]@{
            Ok = $true; Path = $Path; ImgW = $w; ImgH = $h
            ClientLeft = $co.X - $wr.Left; ClientTop = $co.Y - $wr.Top
            ClientW = $cr.Right; ClientH = $cr.Bottom
            AvgLum = $stats.AvgLum; Sig = $stats.Sig; Hash = (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash; Why = ''
        }
    } catch {
        return [pscustomobject]@{ Ok = $false; Why = "截图失败：$($_.Exception.Message)" }
    } finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
    }
}

function Send-GdArkClick {
    <# 往端游客户区某个点发一次左键，返回 @{Mode;Sent}。
       为什么不只靠 PostMessage：2026-09-24 实测过 —— 裸 PostMessage(客户区坐标)消息确实发出去了、
       坐标也正好压在"是否消耗1次联络机会"那个 × 上(模型给的点位偏差只有 2 像素)，弹窗却纹丝不动。
       默认走"抢前台 + 真实点击"是因为它是这台机器上被反复验证有效的那条路；
       抢不到前台才退回 PostMessage —— 宁可点不动，也不能把真实点击漏进用户正在用的窗口。
       （别把这条当成"MAA 也这么点"：MAA 配置里鼠标是 PostMessageWithWindowPos、键盘是 SendMessage，
        它同样在发消息、而且有人在机器前时点得动；但它那个"带窗口位置"的变体和这里裸发客户区坐标是不是一回事，
        还没验过 —— 所以本函数继续把真实鼠标当主路径。） #>
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

function New-GdVisionTarget-ark {
    <# 端游这一路的靶子。命名照 lib\vision-rescue.ps1 的约定，由 Get-GdVisionTarget 找过来。
       Shot/Click 每次都重新找窗口、不在靶子里存句柄：兜底一共要拍两张图、中间还隔 6 秒，
       端游这期间可能被用户关掉 —— 存着的句柄会把"窗口已经没了"变成"PrintWindow 返回 false"，
       前者是一句人话，后者要人去猜。
       开关沿用 arkVisionRescue(不改名：ark 一路的行为和玩家已写的 settings 都不许被这轮改动波及)。 #>
    param([Parameter(Mandatory)]$S, [object]$Conn = $null)
    $on = ($S.runtime.arkVisionRescue -ne $false)
    $shot = {
        param([string]$Path)
        $w = Get-GdArkWindow -S $S
        if (-not $w) { return [pscustomobject]@{ Ok = $false; Why = '端游窗口没找到(可能已经关了)' } }
        return (Save-GdWindowShot -Hwnd $w.Handle -Path $Path)
    }.GetNewClosure()
    $click = {
        param([int]$X, [int]$Y)
        $w = Get-GdArkWindow -S $S
        if (-not $w) { return [pscustomobject]@{ Mode = '端游窗口已消失'; Sent = $false } }
        return (Send-GdArkClick -Hwnd $w.Handle -ClientX $X -ClientY $Y)
    }.GetNewClosure()
    $alive = { return [bool](Get-GdArkWindow -S $S) }.GetNewClosure()
    return [pscustomobject]@{
        Kind       = 'ark'
        Name       = '端游窗口'
        Enabled    = [bool]$on
        Why        = $(if (-not $on) { 'arkVisionRescue=false，视觉兜底已关闭' } else { '' })
        NeedsAdmin = $true
        AdminWhy   = '端游是 requireAdministrator，这个权限下点它不会有任何反应'
        Scene      = ''          # 空 = 用 lib\vision-rescue.ps1 里那段端游默认文案，逐字不许变
        UserText   = ''          # 同上(默认就是"这是端游当前画面…")
        Shot       = $shot
        Click      = $click
        Alive      = $alive
        Grab       = { return (Invoke-GdArkForegroundGrab -S $S) }.GetNewClosure()
    }
}
