# Origin Island - notifikasi ala Dynamic Island untuk Claude Code (WSL) di Windows.
# Jalankan dengan: powershell -NoProfile -ExecutionPolicy Bypass -STA -File island.ps1

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Net.Http
# Aplikasi latar belakang: jangan rebutan CPU dengan aplikasi lain.
try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal' } catch {}

$AppDir = $PSScriptRoot
$cfg = Get-Content -Raw -LiteralPath (Join-Path $AppDir 'config.json') | ConvertFrom-Json
$LogPath = Join-Path $AppDir 'island.log'

function Log($msg) {
    try { Add-Content -LiteralPath $LogPath -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) } catch {}
}

# --- satu instance saja ------------------------------------------------------
$created = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\OriginIsland', [ref]$created)
if (-not $created) { exit }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class IslandNative {
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    public struct RECT { public int L, T, R, B; }

    // ---- Posisi multi-monitor dalam piksel fisik ----
    // Monitor bisa punya skala DPI berbeda (mis. laptop 175% + monitor 100%). Supaya tepat,
    // semua hitungan posisi dilakukan di konteks per-monitor-DPI (piksel asli).
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
    delegate bool MonEnum(IntPtr hMon, IntPtr hdc, ref RECT r, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonEnum cb, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr hMon, ref MONITORINFOEX mi);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MONITORINFOEX {
        public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
    }
    public class Mon { public string Name; public bool Primary; public int L, T, W, H; }

    static IntPtr PerMonitor() {
        try { return SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch { return IntPtr.Zero; }
    }
    static void Restore(IntPtr old) { if (old != IntPtr.Zero) SetThreadDpiAwarenessContext(old); }

    public static Mon[] Monitors() {
        var list = new System.Collections.Generic.List<Mon>();
        IntPtr old = PerMonitor();
        try {
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate (IntPtr h, IntPtr dc, ref RECT r, IntPtr d) {
                var mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
                if (GetMonitorInfo(h, ref mi)) {
                    var w = mi.rcWork;
                    list.Add(new Mon { Name = mi.szDevice, Primary = (mi.dwFlags & 1) != 0, L = w.L, T = w.T, W = w.R - w.L, H = w.B - w.T });
                }
                return true;
            }, IntPtr.Zero);
        } finally { Restore(old); }
        return list.ToArray();
    }
    public static RECT WindowRect(IntPtr h) {
        IntPtr old = PerMonitor();
        try { RECT r; GetWindowRect(h, out r); return r; } finally { Restore(old); }
    }
    public static void MoveTo(IntPtr h, int x, int y) {
        IntPtr old = PerMonitor();
        try {
            // Pindah antar monitor beda skala bisa membuat Windows menggeser jendela; ulangi sekali.
            for (int i = 0; i < 2; i++) {
                SetWindowPos(h, new IntPtr(-1), x, y, 0, 0, 0x0001 | 0x0010);
                RECT r; GetWindowRect(h, out r);
                if (r.L == x && r.T == y) break;
            }
        } finally { Restore(old); }
    }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    public struct POINT { public int X, Y; }
    public static POINT Cursor() {
        IntPtr old = PerMonitor();
        try { POINT p; GetCursorPos(out p); return p; } finally { Restore(old); }
    }

    // Sembunyikan dari Alt-Tab & jangan curi fokus.
    public static void Setup(IntPtr h) { SetWindowLong(h, -20, GetWindowLong(h, -20) | 0x80 | 0x08000000); }
    public static void Top(IntPtr h) { SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); }

    // ---- Membuka (memunculkan) jendela terminal ----
    delegate bool WinEnum(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(WinEnum cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);

    // Munculkan jendela teratas (urutan Z) dengan kelas tertentu. False bila tidak ada.
    public static bool FocusWindowOfClass(string cls) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            var sb = new StringBuilder(128); GetClassName(h, sb, 128);
            if (sb.ToString() == cls) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        if (found == IntPtr.Zero) return false;
        if (IsIconic(found)) ShowWindow(found, 9);   // SW_RESTORE
        SetForegroundWindow(found);
        return true;
    }

    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);

    // Jendela sistem Windows yang transparan selebar layar (bukan video/game sungguhan).
    static readonly string[] ShellClasses = {
        "WorkerW", "Progman", "Shell_TrayWnd", "Shell_SecondaryTrayWnd",
        "IslandWindow",                  // "Click to Do"
        "Windows.UI.Core.CoreWindow",    // panel input/emoji, Start, pencarian, notifikasi
        "XamlExplorerHostIslandWindow", "TopLevelWindowForOverflowXamlIsland", "ForegroundStaging",
        "MultitaskingViewFrame", "TaskSwitcherWnd", "LockScreenBackstopFrame"
    };

    // Nama jendela aktif terakhir yang dianggap fullscreen (untuk log).
    public static string LastFullscreenWindow = "";

    // True bila jendela aktif menutupi seluruh monitor tempat island berada (video/game fullscreen).
    public static bool ForegroundIsFullscreen(IntPtr self) {
        IntPtr f = GetForegroundWindow();
        if (f == IntPtr.Zero || f == self) return false;
        var sb = new StringBuilder(64); GetClassName(f, sb, 64);
        string c = sb.ToString();
        if (Array.IndexOf(ShellClasses, c) >= 0) return false;
        if ((GetWindowLong(f, -20) & 0x80) != 0) return false;            // WS_EX_TOOLWINDOW
        int cloaked;
        if (DwmGetWindowAttribute(f, 14, out cloaked, 4) == 0 && cloaked != 0) return false;   // tak kasatmata
        IntPtr old = PerMonitor();
        try {
            IntPtr mon = MonitorFromWindow(f, 2);
            if (mon != MonitorFromWindow(self, 2)) return false;
            var mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            RECT r;
            if (!GetMonitorInfo(mon, ref mi) || !GetWindowRect(f, out r)) return false;
            var m = mi.rcMonitor;
            bool full = r.L <= m.L && r.T <= m.T && r.R >= m.R && r.B >= m.B;
            if (full) { var t = new StringBuilder(80); GetWindowText(f, t, 80); LastFullscreenWindow = "[" + c + "] " + t; }
            return full;
        } finally { Restore(old); }
    }

    // Kembalikan memori yang tidak terpakai ke Windows (dipanggil sesekali saat pil diam).
    [DllImport("psapi.dll")] static extern bool EmptyWorkingSet(IntPtr h);
    public static void Trim() {
        GC.Collect(); GC.WaitForPendingFinalizers();
        EmptyWorkingSet(System.Diagnostics.Process.GetCurrentProcess().Handle);
    }
}
'@

# --- UI ----------------------------------------------------------------------
# Gaya Dynamic Island: kapsul hitam pekat, tanpa bayangan (bayangan di jendela transparan
# dirender CPU tiap frame - itu penyebab utama berat).
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Origin Island" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" ShowActivated="False"
        Width="420" Height="330" UseLayoutRounding="True">
  <!-- Island = 3 lapis bertumpuk:
       Pill     : latar hitam KOSONG - hanya ini yang ukurannya dianimasikan (murah & mulus).
       Compact  : baris atas, lebarnya mengikuti Pill.
       Expanded : isi panel, lebar tetap, tidak pernah dipotong oleh ukuran Pill.
       CornerRadius diatur dari kode mengikuti tinggi (lihat Update-Radius). -->
  <Grid x:Name="Island" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,6,0,0" Cursor="Hand">
    <Border x:Name="Pill" Background="#000000" CornerRadius="18" BorderBrush="#1AFFFFFF" BorderThickness="1"
            HorizontalAlignment="Center" VerticalAlignment="Top" Width="240" Height="36"/>
    <Grid x:Name="Compact" Height="36" VerticalAlignment="Top" HorizontalAlignment="Center"
          Width="{Binding ElementName=Pill, Path=ActualWidth}">
      <Grid Margin="14,0,10,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="MascotHost" VerticalAlignment="Center" Margin="0,1,0,0"/>
        <TextBlock x:Name="StatusText" Grid.Column="1" Margin="10,0,10,0" Text="Claude"
                   Foreground="#F5F5F7" FontSize="12.5" FontWeight="SemiBold"
                   FontFamily="Segoe UI Variable Text, Segoe UI" VerticalAlignment="Center"
                   TextTrimming="CharacterEllipsis"/>
        <StackPanel x:Name="Trailing" Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center"/>
        <!-- Tombol X: hanya saat pil terbuka. Merah saat disorot/diklik. -->
        <Border x:Name="CloseBtn" Grid.Column="3" Width="22" Height="22" CornerRadius="11" Margin="8,0,0,0"
                Background="Transparent" VerticalAlignment="Center" Visibility="Collapsed"
                ToolTip="Tutup Origin Island (menyala lagi saat Claude dipakai atau terminal WSL dibuka)"/>
      </Grid>
    </Grid>
    <StackPanel x:Name="Expanded" Width="344" Margin="0,46,0,16" HorizontalAlignment="Center"
                VerticalAlignment="Top" Visibility="Collapsed">
      <StackPanel.RenderTransform><TranslateTransform/></StackPanel.RenderTransform>
    </StackPanel>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
foreach ($n in 'Island', 'Pill', 'MascotHost', 'StatusText', 'Trailing', 'Expanded', 'CloseBtn') {
    Set-Variable -Name $n -Value $win.FindName($n) -Scope Script
}

$Font = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Text, Segoe UI')
$Conv = New-Object System.Windows.Media.BrushConverter
$BrushCache = @{}
function Brush($hex) {
    # Brush dibekukan & dipakai ulang: lebih hemat dari membuat objek baru tiap kali.
    $b = $BrushCache[$hex]
    if (-not $b) { $b = $Conv.ConvertFromString($hex); $b.Freeze(); $BrushCache[$hex] = $b }
    $b
}

# Palet ala iOS (mode gelap).
# Accent = warna nyala api maskot ogin (coral), AccentSoft = merah muda lembutnya.
$C = @{
    Accent = '#F45B69'; AccentSoft = '#F7A3AB'; Green = '#30D158'; Amber = '#FF9F0A'; Red = '#FF3B30'
    Text = '#F5F5F7'; Sub = '#A1A1A6'; Dim = '#6E6E73'; Track = '#2C2C2E'
    Button = '#1C1C1E'; ButtonHover = '#2C2C2E'; ButtonDown = '#3A3A3C'; Icon = '#E5E5EA'
}

# --- ikon SVG (folder icons/) -----------------------------------------------
# Mendukung ikon isi (fill) maupun garis (stroke, fill="none"). viewBox dihormati lewat
# Viewbox + Canvas, jadi semua ikon berskala sama rata.
$IconCache = @{}
function Get-IconSpec($name) {
    if ($IconCache.ContainsKey($name)) { return $IconCache[$name] }
    $spec = $null
    try {
        $svg = [System.IO.File]::ReadAllText((Join-Path $AppDir "icons\$name.svg"))
        $paths = [regex]::Matches($svg, '\sd="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        $vb = [regex]::Match($svg, 'viewBox="([^"]+)"').Groups[1].Value -split '[\s,]+' | Where-Object { $_ }
        $sw = [regex]::Match($svg, 'stroke-width="([\d.]+)"')
        $geo = [System.Windows.Media.Geometry]::Parse(($paths -join ' '))
        $geo.Freeze()
        $spec = @{
            Geo = $geo
            W = if ($vb.Count -eq 4) { [double]$vb[2] } else { 24.0 }
            H = if ($vb.Count -eq 4) { [double]$vb[3] } else { 24.0 }
            Stroke = $svg -match 'fill="none"'
            StrokeWidth = if ($sw.Success) { [double]$sw.Groups[1].Value } else { 2.0 }
        }
    }
    catch { Log "ikon $name tidak terbaca: $_" }
    $IconCache[$name] = $spec
    $spec
}

function New-Icon($name, [double]$size, $color) {
    $vbx = New-Object System.Windows.Controls.Viewbox
    $vbx.Width = $size; $vbx.Height = $size
    $spec = Get-IconSpec $name
    if (-not $spec) { return $vbx }
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = $spec.Geo
    if ($spec.Stroke) {
        $p.Stroke = Brush $color; $p.StrokeThickness = $spec.StrokeWidth
        $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'; $p.StrokeLineJoin = 'Round'
    }
    else { $p.Fill = Brush $color }
    $cv = New-Object System.Windows.Controls.Canvas
    $cv.Width = $spec.W; $cv.Height = $spec.H
    [void]$cv.Children.Add($p)
    $vbx.Child = $cv
    $vbx.Tag = $p
    $vbx
}

function Set-IconColor($icon, $color) {
    $p = $icon.Tag
    if (-not $p) { return }
    if ($p.Stroke) { $p.Stroke = Brush $color } else { $p.Fill = Brush $color }
}

# --- maskot "ogin" (icons/ogin-pixel.json) -----------------------------------
# JSON berisi palet + frame 16x16 per status (idle, thinking, working, waiting, done, error)
# dan durasi tiap frame. Tiap frame diubah sekali saat start menjadi DrawingImage vektor yang
# dibekukan; animasinya cukup menukar gambar lewat mesin animasi WPF (tanpa kode per frame).
$Ogin = @{}   # status -> @{ Frames = DrawingImage[]; Ms = int[] }
function Load-Ogin {
    $j = Get-Content -Raw -LiteralPath (Join-Path $AppDir 'icons\ogin-pixel.json') | ConvertFrom-Json
    $size = [int]$j.size
    $pal = @{}
    foreach ($p in $j.palette.PSObject.Properties) { $pal[[string]$p.Name] = Brush $p.Value }
    foreach ($st in $j.states.PSObject.Properties) {
        $frames = foreach ($fr in $st.Value.frames) {
            # Kelompokkan piksel per warna; piksel berurutan dalam satu baris digabung jadi satu persegi.
            $groups = @{}
            for ($y = 0; $y -lt $fr.Count; $y++) {
                $row = [string]$fr[$y]; $x = 0
                while ($x -lt $row.Length) {
                    $ch = [string]$row[$x]
                    if (-not $pal.ContainsKey($ch)) { $x++; continue }
                    $start = $x
                    while ($x -lt $row.Length -and [string]$row[$x] -ceq $ch) { $x++ }
                    if (-not $groups.ContainsKey($ch)) { $groups[$ch] = New-Object System.Windows.Media.GeometryGroup }
                    $groups[$ch].Children.Add((New-Object System.Windows.Media.RectangleGeometry([System.Windows.Rect]::new($start, $y, $x - $start, 1))))
                }
            }
            $dg = New-Object System.Windows.Media.DrawingGroup
            # Kotak transparan seukuran kanvas supaya semua frame berukuran sama (tidak "goyang").
            [void]$dg.Children.Add((New-Object System.Windows.Media.GeometryDrawing((Brush '#00000000'), $null, (New-Object System.Windows.Media.RectangleGeometry([System.Windows.Rect]::new(0, 0, $size, $size))))))
            foreach ($k in $groups.Keys) {
                [void]$dg.Children.Add((New-Object System.Windows.Media.GeometryDrawing($pal[$k], $null, $groups[$k])))
            }
            $img = New-Object System.Windows.Media.DrawingImage($dg)
            $img.Freeze()
            $img
        }
        $Ogin[[string]$st.Name] = @{ Frames = @($frames); Ms = @($st.Value.ms | ForEach-Object { [int]$_ }); Name = [string]$st.Value.name }
    }
}
try { Load-Ogin } catch { Log "maskot ogin gagal dimuat: $_" }

function New-Ogin([double]$size) {
    $im = New-Object System.Windows.Controls.Image
    $im.Width = $size; $im.Height = $size; $im.Stretch = 'Fill'
    [System.Windows.Media.RenderOptions]::SetEdgeMode($im, 'Aliased')   # piksel tetap tajam
    $im
}

# Jalankan animasi status pada sebuah Image (berulang terus).
function Set-OginState($im, $state) {
    $s = $Ogin[$state]
    if (-not $s) { $s = $Ogin['idle'] }
    if (-not $s) { return }
    $im.BeginAnimation([System.Windows.Controls.Image]::SourceProperty, $null)
    $im.Source = $s.Frames[0]
    if ($s.Frames.Count -lt 2) { return }
    $a = New-Object System.Windows.Media.Animation.ObjectAnimationUsingKeyFrames
    $t = 0
    for ($i = 0; $i -lt $s.Frames.Count; $i++) {
        $kt = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($t))
        [void]$a.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteObjectKeyFrame($s.Frames[$i], $kt)))
        $t += $s.Ms[[math]::Min($i, $s.Ms.Count - 1)]
    }
    $a.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($t))
    $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $a.SetValue([System.Windows.Media.Animation.Timeline]::DesiredFrameRateProperty, 20)
    $im.BeginAnimation([System.Windows.Controls.Image]::SourceProperty, $a)
}

$script:Mascot = New-Ogin 30
$MascotHost.Child = $script:Mascot

# --- cincin kuota (gaya Activity Rings) -------------------------------------
function New-Ring([double]$size, [double]$thick, [double]$pct, $color) {
    $g = New-Object System.Windows.Controls.Grid
    $g.Width = $size; $g.Height = $size
    $track = New-Object System.Windows.Shapes.Ellipse
    $track.Stroke = Brush $C.Track; $track.StrokeThickness = $thick
    [void]$g.Children.Add($track)
    $pct = [math]::Max(0.0, [math]::Min(100.0, $pct))
    if ($pct -ge 99.95) {
        $full = New-Object System.Windows.Shapes.Ellipse
        $full.Stroke = Brush $color; $full.StrokeThickness = $thick
        [void]$g.Children.Add($full)
    }
    elseif ($pct -gt 0.5) {
        $r = ($size - $thick) / 2.0; $c = $size / 2.0
        $a = $pct / 100.0 * 2.0 * [math]::PI
        $end = [System.Windows.Point]::new($c + $r * [math]::Sin($a), $c - $r * [math]::Cos($a))
        $seg = New-Object System.Windows.Media.ArcSegment($end, [System.Windows.Size]::new($r, $r), 0.0, ($pct -gt 50), [System.Windows.Media.SweepDirection]::Clockwise, $true)
        $fig = New-Object System.Windows.Media.PathFigure
        $fig.StartPoint = [System.Windows.Point]::new($c, $c - $r)
        [void]$fig.Segments.Add($seg)
        $geo = New-Object System.Windows.Media.PathGeometry
        [void]$geo.Figures.Add($fig)
        $geo.Freeze()
        $arc = New-Object System.Windows.Shapes.Path
        $arc.Data = $geo; $arc.Stroke = Brush $color; $arc.StrokeThickness = $thick
        $arc.StrokeStartLineCap = 'Round'; $arc.StrokeEndLineCap = 'Round'
        [void]$g.Children.Add($arc)
    }
    $g
}

# --- ukuran & animasi --------------------------------------------------------
$CompactW = 240.0
$ExpandedW = 380.0
$CompactH = 36.0
# Pegas halus: sedikit memantul seperti Dynamic Island, tidak berlebihan.
$Spring = New-Object System.Windows.Media.Animation.BackEase -Property @{ Amplitude = 0.18; EasingMode = 'EaseOut' }
$Smooth = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = 'EaseOut' }
$Spring.Freeze(); $Smooth.Freeze()
$FrameRateProp = [System.Windows.Media.Animation.Timeline]::DesiredFrameRateProperty

function Animate($el, $prop, [double]$to, [int]$ms, $ease, [int]$delay = 0, [int]$fps = 60) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.To = $to
    $a.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($ms))
    $a.BeginTime = [TimeSpan]::FromMilliseconds($delay)
    if ($ease) { $a.EasingFunction = $ease }
    $a.SetValue($FrameRateProp, $fps)
    $el.BeginAnimation($prop, $a)
}

# --- state -------------------------------------------------------------------
$script:sessions = @{}         # session_id -> @{ project; state; ts; cwd; distro; term }
$script:notif = $null          # @{ kind; title; project; body; term; cwd; distro }
$script:notifUntil = [datetime]::MinValue
$script:isExpanded = $false
$script:confirmUninstall = $false
$script:hover = $false
$script:leaveAt = [datetime]::MinValue
$script:mascotMode = ''
$script:errorFlashUntil = [datetime]::MinValue
$script:compactKey = ''
$script:trailingKey = ''
$script:expandedKey = $null   # kunci isi panel yang sedang dibangun (untuk cache)
$script:expandedDirty = $true
$script:targetH = 0
$script:lastTrim = [datetime]::Now
$script:sound = if ($null -ne $cfg.sound) { [bool]$cfg.sound } else { $true }
$script:usage = $null
$script:usageAt = $null
$script:usageErr = $null
$script:usageNote = $null      # info lunak (mis. kena 429) - data lama tetap ditampilkan
$script:usageSource = $null    # 'Claude Code' (statusline) atau 'API'
$script:usageFileTime = [datetime]::MinValue
$script:lastUsageCheck = [datetime]::MinValue
$script:apiBackoff = 0         # menit; naik 5 -> 10 -> 20 -> 30 tiap kena 429
$script:forceApi = $false
$script:usageTask = $null
$script:nextUsage = [datetime]::Now
$script:token = $null
$script:tokenExp = 0
$script:forceToken = $false
$script:lastHousekeep = [datetime]::MinValue
$script:lastWslCheck = [datetime]::MinValue
$script:hiddenForFullscreen = $false
$script:fullscreenHits = 0
$script:evFile = New-Object System.IO.FileInfo($cfg.eventsPath)
$script:evOffset = if ($script:evFile.Exists) { $script:evFile.Length } else { 0 }

# Suara notifikasi: file sendiri (mp3/wav, lewat MediaPlayer WPF), cadangannya suara Windows.
function Resolve-Sound($configured, $bundled) {
    if ($configured) { return [string]$configured }
    Join-Path $AppDir "sounds\$bundled"
}
$SoundDone = Resolve-Sound $cfg.soundDone 'claude-selesai.mp3'
$SoundAttention = Resolve-Sound $cfg.soundAttention 'claude-butuh-izin.mp3'
$SoundVolume = if ($null -ne $cfg.soundVolume) { [double]$cfg.soundVolume } else { 1.0 }

# Kuota datang dari statusline Claude Code (fitur resmi, tanpa request tambahan) lewat usage.json.
# API usage (endpoint tidak resmi + membaca token OAuth) hanya cadangan dan MATI secara default;
# nyalakan dengan "usageApiFallback": true di config.json. Bila nyala: hanya saat data statusline
# basi, paling cepat tiap 5 menit.
$UsagePath = if ($cfg.usagePath) { $cfg.usagePath } else { Join-Path (Split-Path $cfg.eventsPath) 'usage.json' }
$UseApiFallback = [bool]$cfg.usageApiFallback
$PollSeconds = [math]::Max(300.0, [double]$cfg.pollSeconds)
$FreshMinutes = 10

# --- posisi & monitor --------------------------------------------------------
# Pil selalu menempel di tepi atas; user menggesernya kiri/kanan sendiri.
# position.json: { device, x } -> monitor + posisi kiri jendela (piksel fisik) persis seperti
# ditinggalkan user. Tanpa file itu (atau monitornya hilang): tengah atas monitor utama.
$PositionPath = Join-Path $AppDir 'position.json'
$AlivePath = Join-Path $AppDir 'alive'
$script:screenSig = ''
$script:wslDownSince = $null
$ExitWhenWslStops = if ($null -ne $cfg.exitWhenWslStops) { [bool]$cfg.exitWhenWslStops } else { $true }

function Hwnd { (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle }

function Load-Position {
    if (-not (Test-Path -LiteralPath $PositionPath)) { return $null }
    try { Get-Content -Raw -LiteralPath $PositionPath | ConvertFrom-Json } catch { $null }
}

function Place-Island {
    $mons = @([IslandNative]::Monitors())
    if ($mons.Count -eq 0) { return }
    $pos = Load-Position
    $m = $null
    if ($pos) { $m = $mons | Where-Object { $_.Name -eq $pos.device } | Select-Object -First 1 }
    if (-not $m) { $pos = $null; $m = $mons | Where-Object { $_.Primary } | Select-Object -First 1 }
    if (-not $m) { $m = $mons[0] }
    $r = [IslandNative]::WindowRect((Hwnd))
    $w = $r.R - $r.L
    if ($pos) {
        # Jaga agar titik tengah pil tetap di dalam monitor itu (mis. resolusi berubah).
        $x = [math]::Min($m.L + $m.W - $w / 2, [math]::Max($m.L - $w / 2, [double]$pos.x))
    }
    else { $x = $m.L + ($m.W - $w) / 2 }
    [IslandNative]::MoveTo((Hwnd), [int]$x, $m.T)
}

# Monitor yang memuat titik tengah pil.
function Monitor-At([int]$cx) {
    $all = @([IslandNative]::Monitors())
    $m = $all | Where-Object { $cx -ge $_.L -and $cx -lt $_.L + $_.W } | Select-Object -First 1
    if (-not $m) { $m = $all | Where-Object { $_.Primary } | Select-Object -First 1 }
    $m
}

function Save-Position {
    $r = [IslandNative]::WindowRect((Hwnd))
    $m = Monitor-At ($r.L + ($r.R - $r.L) / 2)
    if (-not $m) { return }
    [IslandNative]::MoveTo((Hwnd), $r.L, $m.T)   # menempel ke tepi atas monitor itu
    @{ device = $m.Name; x = $r.L } | ConvertTo-Json | Set-Content -LiteralPath $PositionPath -Encoding UTF8
}

# Ke tengah atas monitor tempat pil SEKARANG berada (bukan selalu monitor utama), lalu simpan.
function Center-OnCurrentMonitor {
    $r = [IslandNative]::WindowRect((Hwnd))
    $w = $r.R - $r.L
    $m = Monitor-At ($r.L + $w / 2)
    if (-not $m) { return }
    [IslandNative]::MoveTo((Hwnd), [int]($m.L + ($m.W - $w) / 2), $m.T)
    Save-Position
    Log "ke tengah: $($m.Name)$(if ($m.Primary) { ' (utama)' })"
}

# --- seret kiri/kanan --------------------------------------------------------
$script:drag = $null   # @{ cursorX; winL; moved }

function Drag-Start {
    $r = [IslandNative]::WindowRect((Hwnd))
    $script:drag = @{ cursorX = [IslandNative]::Cursor().X; winL = $r.L; moved = $false }
    [void]$Island.CaptureMouse()
}

function Drag-Move {
    $d = $script:drag
    if (-not $d) { return }
    $dx = [IslandNative]::Cursor().X - $d.cursorX
    if (-not $d.moved -and [math]::Abs($dx) -lt 6) { return }   # belum dihitung geser
    $d.moved = $true
    $x = $d.winL + $dx
    $r = [IslandNative]::WindowRect((Hwnd))
    $m = Monitor-At ($x + ($r.R - $r.L) / 2)
    $y = if ($m) { $m.T } else { $r.T }
    [IslandNative]::MoveTo((Hwnd), [int]$x, [int]$y)
}

function Drag-End {
    $d = $script:drag
    $script:drag = $null
    $Island.ReleaseMouseCapture()
    if (-not $d) { return }
    if ($d.moved) { Save-Position; return }
    # Klik biasa: buka terminal sesi terkait (notifikasi, atau sesi paling relevan).
    $target = $script:notif
    if (-not $target) {
        $all = @($script:sessions.Values)
        $target = @($all | Where-Object { $_.state -eq 'attention' }) + @($all | Sort-Object { $_.ts } -Descending) | Select-Object -First 1
    }
    if ($target) { Open-Terminal $target }
    if ($script:notif) { Dismiss-Notif }
}

# Munculkan terminal tempat sesi berjalan. $t butuh: term ('wt'/'vscode'), cwd, distro.
function Open-Terminal($t) {
    try {
        if ($t.term -eq 'vscode' -and $t.cwd -and $t.distro) {
            # Membuka folder yang sama = VS Code memunculkan jendela yang sudah membuka folder itu.
            $code = Get-Command code.cmd, code -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($code) {
                $uri = "vscode-remote://wsl+$($t.distro)$($t.cwd)"
                Start-Process -FilePath $code.Source -ArgumentList '--folder-uri', $uri -WindowStyle Hidden
                return
            }
        }
        if (-not [IslandNative]::FocusWindowOfClass('CASCADIA_HOSTING_WINDOW_CLASS')) {
            Log 'Open-Terminal: jendela Windows Terminal tidak ditemukan'
        }
    }
    catch { Log "Open-Terminal: $_" }
}

function Screen-Signature {
    ([IslandNative]::Monitors() | ForEach-Object { "$($_.Name)|$($_.Primary)|$($_.L),$($_.T),$($_.W),$($_.H)" }) -join ';'
}

function Wsl-IsRunning {
    ([System.Diagnostics.Process]::GetProcessesByName('vmmemWSL').Length +
    [System.Diagnostics.Process]::GetProcessesByName('vmmem').Length) -gt 0
}

# --- helper UI ---------------------------------------------------------------
function New-Text($text, [double]$size, $color, $weight = 'Normal') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text; $t.FontSize = $size; $t.Foreground = Brush $color
    $t.FontFamily = $Font; $t.FontWeight = $weight
    $t.TextTrimming = 'CharacterEllipsis'
    $t
}

function Severity-Color([double]$pct, $normal = $C.Accent) {
    if ($pct -ge 90) { return $C.Red }
    if ($pct -ge 75) { return $C.Amber }
    return $normal
}

function To-Local($v) {
    if (-not $v) { return $null }
    if ($v -is [datetime]) { return $v.ToLocalTime() }
    try { return [DateTimeOffset]::Parse([string]$v).LocalDateTime } catch { return $null }
}

# Hasil: @{ Short = 'reset 2j 33m'; Full = 'Reset dalam 2j 33m (12:50)' }
function Format-Reset($v) {
    $t = To-Local $v
    if (-not $t) { return $null }
    $d = $t - [datetime]::Now
    if ($d.TotalSeconds -le 0) { return @{ Short = 'reset sebentar'; Full = 'Reset sebentar lagi' } }
    if ($d.TotalDays -ge 1) { $span = '{0}h {1}j' -f [int][math]::Floor($d.TotalDays), $d.Hours }
    elseif ($d.TotalHours -ge 1) { $span = '{0}j {1}m' -f [int][math]::Floor($d.TotalHours), $d.Minutes }
    else { $span = '{0}m' -f [int][math]::Ceiling($d.TotalMinutes) }
    $when = if ($d.TotalDays -ge 1) { $t.ToString('ddd HH:mm', [Globalization.CultureInfo]'id-ID') } else { $t.ToString('HH:mm') }
    @{ Short = "reset $span"; Full = "Reset dalam $span ($when)" }
}

function Get-Limits {
    $u = $script:usage
    $list = New-Object System.Collections.ArrayList
    if (-not $u) { return , $list }
    $labels = [ordered]@{
        five_hour = 'Sesi 5 jam'; seven_day = 'Mingguan'
        seven_day_opus = 'Opus'; seven_day_sonnet = 'Sonnet'
    }
    foreach ($k in $labels.Keys) {
        $v = $u.$k
        if ($v -and $null -ne $v.utilization) {
            [void]$list.Add([pscustomobject]@{ Label = $labels[$k]; Pct = [double]$v.utilization; Reset = $v.resets_at })
        }
    }
    $x = $u.extra_usage
    if ($x -and $x.is_enabled -and $null -ne $x.utilization) {
        [void]$list.Add([pscustomobject]@{ Label = 'Extra'; Pct = [double]$x.utilization; Reset = $null })
    }
    return , $list
}

# Satu "ubin" kuota: cincin besar + persen di tengah, label, dan sisa waktu reset.
function New-RingTile($l) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.HorizontalAlignment = 'Center'
    $ring = New-Ring 48 5 $l.Pct (Severity-Color $l.Pct)
    $ring.HorizontalAlignment = 'Center'
    $pt = New-Text ('{0:0}%' -f $l.Pct) 12.5 $C.Text 'SemiBold'
    $pt.HorizontalAlignment = 'Center'; $pt.VerticalAlignment = 'Center'
    [void]$ring.Children.Add($pt)
    [void]$sp.Children.Add($ring)
    $lb = New-Text $l.Label 11.5 $C.Text
    $lb.HorizontalAlignment = 'Center'; $lb.Margin = '0,7,0,0'
    [void]$sp.Children.Add($lb)
    $r = Format-Reset $l.Reset
    if ($r) {
        $rt = New-Text $r.Short 10 $C.Dim
        $rt.HorizontalAlignment = 'Center'
        [void]$sp.Children.Add($rt)
        $sp.ToolTip = "$($l.Label): $('{0:0}' -f $l.Pct)% - $($r.Full)"
    }
    $sp
}

function Add-Separator([double]$top = 12, [double]$bottom = 12) {
    $s = New-Object System.Windows.Controls.Border
    $s.Height = 1; $s.Background = Brush '#1AFFFFFF'; $s.Margin = "0,$top,0,$bottom"
    [void]$Expanded.Children.Add($s)
}

# Tombol ikon bulat ala iOS. $onClick = $null -> redup & tidak bisa diklik.
# -Danger: ikon & latar memerah saat disorot (untuk aksi berbahaya seperti uninstall).
function New-IconButton($icon, $tip, $onClick, $iconColor = $C.Icon, [switch]$Danger) {
    $b = New-Object System.Windows.Controls.Border
    $b.Width = 30; $b.Height = 30; $b.CornerRadius = 15; $b.Margin = '6,0,0,0'
    $b.Background = Brush $C.Button
    $ic = New-Icon $icon 15 $iconColor
    $ic.HorizontalAlignment = 'Center'; $ic.VerticalAlignment = 'Center'
    $b.Child = $ic
    $b.ToolTip = $tip
    if (-not $onClick) { $b.Opacity = 0.35; return $b }
    $b.Cursor = 'Hand'
    $b.Tag = $onClick
    if ($Danger) {
        $b.Add_MouseEnter({ $this.Background = Brush '#33FF3B30'; Set-IconColor $this.Child $C.Red })
        $b.Add_MouseLeave({ $this.Background = Brush $C.Button; Set-IconColor $this.Child $C.Icon })
    }
    else {
        $b.Add_MouseEnter({ $this.Background = Brush $C.ButtonHover })
        $b.Add_MouseLeave({ $this.Background = Brush $C.Button })
    }
    # Handled = true: klik tombol tidak dianggap mulai menyeret pil.
    $b.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; $s.Background = Brush $C.ButtonDown })
    $b.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; $s.Background = Brush $C.ButtonHover; & $s.Tag })
    $b
}

function Add-SessionRows {
    $active = @($script:sessions.Values | Sort-Object { $_.ts } -Descending | Select-Object -First 4)
    if ($active.Count -eq 0) { return }
    Add-Separator 14 8
    foreach ($s in $active) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = '-6,0,-6,0'
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 7; $dot.Height = 7; $dot.Margin = '6,0,9,0'; $dot.VerticalAlignment = 'Center'
        switch ($s.state) {
            'working' { $dot.Fill = Brush $C.Accent; $st = 'bekerja' }
            'attention' { $dot.Fill = Brush $C.Amber; $st = 'butuh izin' }
            'done' { $dot.Fill = Brush $C.Green; $st = 'selesai' }
            default { $dot.Fill = Brush $C.Dim; $st = 'siap' }
        }
        [void]$row.Children.Add($dot)
        $stt = New-Text $st 11.5 $C.Sub
        $stt.Margin = '0,0,6,0'
        [System.Windows.Controls.DockPanel]::SetDock($stt, 'Right')
        [void]$row.Children.Add($stt)
        [void]$row.Children.Add((New-Text $s.project 12 $C.Text))
        # Klik baris sesi = buka terminalnya.
        $wrap = New-Object System.Windows.Controls.Border
        $wrap.CornerRadius = 8; $wrap.Padding = '0,5,0,5'; $wrap.Margin = '-6,0,-6,0'
        $wrap.Background = Brush '#00FFFFFF'
        $wrap.Child = $row
        $row.Margin = '0'
        $wrap.Cursor = 'Hand'
        $wrap.ToolTip = 'Klik untuk membuka terminal'
        $wrap.Tag = $s
        $wrap.Add_MouseEnter({ $this.Background = Brush '#14FFFFFF' })
        $wrap.Add_MouseLeave({ $this.Background = Brush '#00FFFFFF' })
        $wrap.Add_MouseLeftButtonDown({ param($snd, $ev) $ev.Handled = $true })
        $wrap.Add_MouseLeftButtonUp({ param($snd, $ev) $ev.Handled = $true; Open-Terminal $snd.Tag })
        [void]$Expanded.Children.Add($wrap)
    }
}

# Tombol teks berbentuk kapsul (untuk konfirmasi).
function New-TextButton($label, $bg, $hoverBg, $fg, $onClick) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = 14; $b.Padding = '14,6,14,7'; $b.Margin = '6,0,0,0'
    $b.Background = Brush $bg
    $t = New-Text $label 12 $fg 'SemiBold'
    $b.Child = $t
    $b.Cursor = 'Hand'
    $b.Tag = @{ Click = $onClick; Bg = $bg; Hover = $hoverBg }
    $b.Add_MouseEnter({ $this.Background = Brush $this.Tag.Hover })
    $b.Add_MouseLeave({ $this.Background = Brush $this.Tag.Bg })
    $b.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true })
    $b.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; & $s.Tag.Click })
    $b
}

# Uninstall lewat tombol: jalankan skrip uninstall di WSL (salinannya ada di ~/.claude/island,
# jadi tetap bisa walau folder repo sudah dihapus), lalu island menutup dirinya sendiri.
$CanUninstall = [bool]($cfg.distro -and $cfg.hookDir)
function Start-Uninstall {
    try {
        # C:\Users\x\AppData\Local\OriginIsland -> /mnt/c/Users/x/AppData/Local/OriginIsland
        $appWsl = '/mnt/' + $AppDir.Substring(0, 1).ToLower() + ($AppDir.Substring(2) -replace '\\', '/')
        $uninstaller = "$($cfg.hookDir)/island_uninstall.sh"
        # wsl.exe yang dijalankan tersembunyi gagal (-1) bila tidak punya tempat menulis output,
        # jadi output-nya dialihkan ke log di %TEMP% (bukan folder aplikasi yang akan dihapus).
        $uninstallLog = Join-Path $env:TEMP 'origin-island-uninstall.log'
        # Nama distro tanpa tanda kutip (wsl.exe ikut membaca kutipnya; nama distro tidak berisi spasi).
        $cmd = '"{0}" /c wsl.exe -d {1} -e bash "{2}" "{3}" > "{4}" 2>&1' -f $env:ComSpec, $cfg.distro, $uninstaller, $appWsl, $uninstallLog
        Log "uninstall dimulai lewat tombol (log: $uninstallLog)"
        [void](New-Object -ComObject WScript.Shell).Run($cmd, 0, $false)
        $win.Close()
    }
    catch { Log "uninstall gagal: $_" }
}

function Add-Footer {
    $foot = New-Object System.Windows.Controls.DockPanel
    $foot.Margin = '0,14,0,0'

    if ($script:confirmUninstall) {
        # Konfirmasi dulu supaya tidak ter-uninstall karena salah klik.
        $btns = New-Object System.Windows.Controls.StackPanel
        $btns.Orientation = 'Horizontal'
        [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
        [void]$btns.Children.Add((New-TextButton 'Batal' $C.Button $C.ButtonHover $C.Text { $script:confirmUninstall = $false; Refresh-UI }))
        [void]$btns.Children.Add((New-TextButton 'Hapus' '#D92D20' '#F04438' '#FFFFFF' { Start-Uninstall }))
        [void]$foot.Children.Add($btns)
        $q = New-Text 'Hapus Origin Island dari laptop ini? Hook Claude Code ikut dilepas.' 11.5 $C.Text
        $q.TextWrapping = 'Wrap'; $q.VerticalAlignment = 'Center'
        [void]$foot.Children.Add($q)
        [void]$Expanded.Children.Add($foot)
        return
    }

    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'
    [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
    if (-not $UseApiFallback) {
        # Tanpa API: baca ulang data kuota terakhir dari statusline Claude Code.
        [void]$btns.Children.Add((New-IconButton 'refresh' 'Muat ulang kuota dari Claude Code' {
                    $script:usageFileTime = [datetime]::MinValue; $script:usageAt = $null
                    Read-UsageFile
                }))
    }
    elseif ($script:apiBackoff -gt 0) {
        [void]$btns.Children.Add((New-IconButton 'refresh' ('Server membatasi cek kuota - coba lagi {0:HH:mm}' -f $script:nextUsage) $null))
    }
    else {
        [void]$btns.Children.Add((New-IconButton 'refresh' 'Perbarui kuota sekarang' {
                    $script:forceApi = $true; $script:nextUsage = [datetime]::Now
                }))
    }
    if ($script:sound) {
        [void]$btns.Children.Add((New-IconButton 'sound-on' 'Suara nyala - klik untuk mematikan' { Toggle-Sound }))
    }
    else {
        [void]$btns.Children.Add((New-IconButton 'sound-off' 'Suara mati - klik untuk menyalakan' { Toggle-Sound } $C.Dim))
    }
    [void]$btns.Children.Add((New-IconButton 'bell' 'Tes suara notifikasi' { Play-Sound 'done' -Force }))
    [void]$btns.Children.Add((New-IconButton 'center' 'Ke tengah layar ini (layar tempat island berada)' { Center-OnCurrentMonitor }))
    if ($CanUninstall) {
        [void]$btns.Children.Add((New-IconButton 'trash' 'Uninstall Origin Island' { $script:confirmUninstall = $true; Refresh-UI } -Danger))
    }
    [void]$foot.Children.Add($btns)

    if ($script:usageErr) { $ft = New-Text $script:usageErr 10.5 $C.Red; $ft.TextWrapping = 'Wrap' }
    elseif ($script:usageAt) {
        $fmt = if ($script:usageAt.Date -eq [datetime]::Today) { 'HH:mm' } else { 'd MMM HH:mm' }
        $when = $script:usageAt.ToString($fmt, [Globalization.CultureInfo]'id-ID')
        $ft = New-Text ('{0}  ·  {1}' -f $script:usageSource, $when) 10.5 $C.Dim
        $ft.ToolTip = 'Sumber & waktu data kuota terakhir'
    }
    else { $ft = New-Text '' 10.5 $C.Dim }
    $ft.VerticalAlignment = 'Center'
    [void]$foot.Children.Add($ft)
    [void]$Expanded.Children.Add($foot)
}

function Build-Expanded {
    $Expanded.Children.Clear()
    $limits = Get-Limits

    if ($script:notif) {
        # --- tampilan notifikasi (Live Activity) ---
        $n = $script:notif
        $color = switch ($n.kind) { 'done' { $C.Green } 'error' { $C.Red } default { $C.Amber } }
        $glyph = if ($n.kind -eq 'done') { [string][char]0x2713 } else { '!' }

        $head = New-Object System.Windows.Controls.DockPanel
        $icon = New-Object System.Windows.Controls.Grid
        $icon.Width = 48; $icon.Height = 48; $icon.Margin = '-4,-6,10,0'; $icon.VerticalAlignment = 'Top'
        $big = New-Ogin 48
        Set-OginState $big $(switch ($n.kind) { 'done' { 'done' } 'error' { 'error' } default { 'waiting' } })
        $big.HorizontalAlignment = 'Left'; $big.VerticalAlignment = 'Top'
        [void]$icon.Children.Add($big)
        $badge = New-Object System.Windows.Controls.Border
        $badge.Width = 16; $badge.Height = 16; $badge.CornerRadius = 8; $badge.Background = Brush $color
        $badge.BorderBrush = Brush '#000000'; $badge.BorderThickness = 2
        $badge.HorizontalAlignment = 'Right'; $badge.VerticalAlignment = 'Bottom'
        $gt = New-Text $glyph 8.5 '#000000' 'Bold'
        $gt.HorizontalAlignment = 'Center'; $gt.VerticalAlignment = 'Center'
        $badge.Child = $gt
        [void]$icon.Children.Add($badge)
        [void]$head.Children.Add($icon)

        $titles = New-Object System.Windows.Controls.StackPanel
        [void]$titles.Children.Add((New-Text $n.title 14 $C.Text 'SemiBold'))
        [void]$titles.Children.Add((New-Text $n.project 11.5 $C.Sub))
        if ($n.body) {
            $b = New-Text $n.body 12 '#D1D1D6'
            $b.TextWrapping = 'Wrap'; $b.MaxHeight = 50; $b.Margin = '0,6,0,0'
            [void]$titles.Children.Add($b)
        }
        $hint = New-Text 'Klik untuk membuka terminal' 10.5 $C.Dim
        $hint.Margin = '0,5,0,0'
        [void]$titles.Children.Add($hint)
        [void]$head.Children.Add($titles)
        [void]$Expanded.Children.Add($head)

        # Ringkasan kuota satu baris.
        if ($limits.Count -gt 0) {
            Add-Separator 12 10
            $line = New-Object System.Windows.Controls.StackPanel
            $line.Orientation = 'Horizontal'
            foreach ($l in @($limits | Select-Object -First 2)) {
                $rg = New-Ring 14 2.5 $l.Pct (Severity-Color $l.Pct)
                $rg.Margin = '0,0,6,0'
                [void]$line.Children.Add($rg)
                $tx = New-Text ('{0} {1:0}%' -f $l.Label, $l.Pct) 11 $C.Sub
                $tx.Margin = '0,0,16,0'; $tx.VerticalAlignment = 'Center'
                [void]$line.Children.Add($tx)
            }
            [void]$Expanded.Children.Add($line)
        }
        return
    }

    # --- tampilan hover: cincin kuota, sesi, tombol ---
    if ($limits.Count -gt 0) {
        $grid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $grid.Columns = [math]::Min(4, $limits.Count)
        $grid.Margin = '0,4,0,0'
        foreach ($l in $limits) { [void]$grid.Children.Add((New-RingTile $l)) }
        [void]$Expanded.Children.Add($grid)
    }
    elseif (-not $script:usageErr) {
        $wait = New-Text $(if ($UseApiFallback) { 'Memuat kuota...' } else { 'Kuota muncul setelah Anda memakai Claude Code' }) 12 $C.Sub
        $wait.Margin = '0,4,0,0'
        [void]$Expanded.Children.Add($wait)
    }
    if ($script:usageNote -and -not $script:usageErr) {
        $nt = New-Text $script:usageNote 10.5 $C.Amber
        $nt.Margin = '0,10,0,0'; $nt.HorizontalAlignment = 'Center'
        [void]$Expanded.Children.Add($nt)
    }
    Add-SessionRows
    Add-Footer
}

function Toggle-Sound {
    $script:sound = -not $script:sound
    Save-Config 'sound' $script:sound
    Refresh-UI
}

function Save-Config($key, $value) {
    try {
        $c = Get-Content -Raw -LiteralPath (Join-Path $AppDir 'config.json') | ConvertFrom-Json
        $c | Add-Member -NotePropertyName $key -NotePropertyValue $value -Force
        $c | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $AppDir 'config.json') -Encoding UTF8
    }
    catch { Log "simpan config: $_" }
}

# Kunci isi panel: bila sama dengan yang sudah dibangun, panel tidak dibangun ulang.
function Get-ExpandedKey {
    $n = $script:notif
    $limits = Get-Limits   # ArrayList; dipipe dari variabel supaya isinya terurai
    $parts = @(
        $(if ($n) { "$($n.kind)|$($n.title)|$($n.project)|$($n.body)" } else { '-' }),
        (($limits | ForEach-Object { $r = Format-Reset $_.Reset; "$($_.Label)=$([math]::Round($_.Pct))/$($r.Short)" }) -join ','),
        (($script:sessions.Values | Sort-Object { $_.ts } -Descending | Select-Object -First 4 | ForEach-Object { "$($_.project):$($_.state)" }) -join ','),
        $script:sound, $script:apiBackoff, $script:usageErr, $script:usageNote, $script:usageSource, $script:confirmUninstall,
        $(if ($script:usageAt) { $script:usageAt.ToString('dd HH:mm') })
    )
    $parts -join '#'
}

# Bangun isi panel hanya bila datanya berubah. Membuat elemen WPF dari PowerShell itu lambat,
# jadi sebisa mungkin dikerjakan saat pil sedang diam (lihat Tick), bukan saat animasi.
function Ensure-Expanded {
    $key = Get-ExpandedKey
    if ($key -ne $script:expandedKey) {
        Build-Expanded
        $script:expandedKey = $key
    }
    $script:expandedDirty = $false
}

function Expand {
    $wasExpanded = $script:isExpanded
    $script:isExpanded = $true
    Update-Compact
    Ensure-Expanded
    $Expanded.Visibility = 'Visible'
    $CloseBtn.Visibility = 'Visible'
    # Tinggi diukur dengan lebar isi yang sebenarnya (Width tetap di XAML) + margin.
    $Expanded.Measure((New-Object System.Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)))
    $h = [math]::Ceiling($Expanded.DesiredSize.Height) + 2
    # Nama variabel PowerShell tidak peka huruf besar/kecil: jangan pakai $H untuk properti
    # karena akan menimpa $h (tinggi).
    $widthProp = [System.Windows.FrameworkElement]::WidthProperty
    $heightProp = [System.Windows.FrameworkElement]::HeightProperty
    if (-not $wasExpanded) {
        Animate $Pill $widthProp $ExpandedW 420 $Spring
        Animate $Pill $heightProp $h 420 $Spring
        # Isi muncul sedikit dari atas sambil memudar masuk, setelah latar mulai membesar.
        $Expanded.Opacity = 0
        Animate $Expanded ([System.Windows.UIElement]::OpacityProperty) 1 220 $Smooth 110
        $tt = $Expanded.RenderTransform
        $tt.Y = -6
        Animate $tt ([System.Windows.Media.TranslateTransform]::YProperty) 0 300 $Smooth 90
    }
    elseif ([math]::Abs($h - $script:targetH) -gt 0.5) {
        Animate $Pill $heightProp $h 260 $Smooth   # isi berubah saat terbuka: sesuaikan tinggi saja
    }
    $script:targetH = $h
}

function Collapse {
    $script:isExpanded = $false
    $script:targetH = 0
    if ($script:confirmUninstall) { $script:confirmUninstall = $false; $script:expandedDirty = $true }   # batal otomatis
    $Expanded.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $Expanded.Visibility = 'Collapsed'   # isi tetap disimpan (cache) untuk hover berikutnya
    $CloseBtn.Visibility = 'Collapsed'
    Update-Compact
    Animate $Pill ([System.Windows.FrameworkElement]::WidthProperty) $CompactW 340 $Smooth
    Animate $Pill ([System.Windows.FrameworkElement]::HeightProperty) $CompactH 340 $Smooth
}

# Status maskot: idle, thinking, working, waiting, done, error (lihat ogin-pixel.json).
function Set-MascotMode($mode) {
    if ($mode -eq $script:mascotMode) { return }
    $script:mascotMode = $mode
    Set-OginState $script:Mascot $mode
}

# Sisi kanan pil: cincin ganda kecil (luar = sesi 5 jam, dalam = mingguan) + persen.
function Update-Trailing($limits) {
    $p5 = if ($limits.Count -gt 0) { [double]$limits[0].Pct } else { -1.0 }
    $p7 = if ($limits.Count -gt 1) { [double]$limits[1].Pct } else { -1.0 }
    $key = "$p5|$p7|$($script:usageErr -ne $null)"
    if ($key -eq $script:trailingKey) { return }
    $script:trailingKey = $key
    $Trailing.Children.Clear()
    if ($p5 -lt 0) {
        if ($script:usageErr) { [void]$Trailing.Children.Add((New-Text '!' 13 $C.Red 'Bold')) }
        return
    }
    $rings = New-Object System.Windows.Controls.Grid
    $rings.Width = 19; $rings.Height = 19
    [void]$rings.Children.Add((New-Ring 19 2.6 $p5 (Severity-Color $p5)))
    if ($p7 -ge 0) {
        $inner = New-Ring 10 2.4 $p7 (Severity-Color $p7 $C.AccentSoft)
        $inner.HorizontalAlignment = 'Center'; $inner.VerticalAlignment = 'Center'
        [void]$rings.Children.Add($inner)
    }
    [void]$Trailing.Children.Add($rings)
    $pct = New-Text ('{0:0}%' -f $p5) 12 $(Severity-Color $p5 $C.Sub) 'SemiBold'
    $pct.Margin = '7,0,0,0'; $pct.VerticalAlignment = 'Center'
    [void]$Trailing.Children.Add($pct)
    $Trailing.ToolTip = ($limits | ForEach-Object { '{0}: {1:0}%' -f $_.Label, $_.Pct }) -join "`n"
}

function Update-Compact {
    $all = @($script:sessions.Values)
    $att = @($all | Where-Object { $_.state -eq 'attention' })
    $work = @($all | Where-Object { $_.state -eq 'working' })

    # Saat bekerja: 'working' bila ada alat yang sedang berjalan, selain itu 'thinking'.
    $workMode = if (@($work | Where-Object { $_.activity -eq 'tool' }).Count -gt 0) { 'working' } else { 'thinking' }
    $n = $script:notif

    if ($n -and $n.kind -eq 'error') { $mode = 'error'; $text = "Gagal  ·  $($n.project)" }
    elseif ($att.Count -gt 0) { $mode = 'waiting'; $text = "Butuh izin  ·  $($att[0].project)" }
    elseif ([datetime]::Now -lt $script:errorFlashUntil -and $work.Count -gt 0) { $mode = 'error'; $text = "Alat gagal  ·  $($work[0].project)" }
    elseif ($work.Count -gt 1) { $mode = $workMode; $text = "$($work.Count) sesi bekerja" }
    elseif ($work.Count -eq 1) { $mode = $workMode; $text = "$(if ($workMode -eq 'working') { 'Bekerja' } else { 'Berpikir' })  ·  $($work[0].project)" }
    elseif ($n -and $n.kind -eq 'done') { $mode = 'done'; $text = "Selesai  ·  $($n.project)" }
    else {
        # Teks idle = nama status 'idle' di ogin-pixel.json ("Siaga").
        $mode = 'idle'; $text = if ($Ogin['idle'] -and $Ogin['idle'].Name) { $Ogin['idle'].Name } else { 'Siaga' }
    }

    Set-MascotMode $mode
    Update-Trailing (Get-Limits)
    if ($text -ne $script:compactKey) { $script:compactKey = $text; $StatusText.Text = $text }
}

function Refresh-UI {
    Update-Compact
    if ($script:isExpanded) { Expand }
    else { $script:expandedDirty = $true }   # dibangun ulang di Tick saat pil diam
}

$script:player = New-Object System.Windows.Media.MediaPlayer
$script:player.Add_MediaFailed({ param($s, $e) Log "suara gagal diputar: $($e.ErrorException.Message)"; Play-WindowsSound $script:lastSoundKind })

function Play-WindowsSound($kind) {
    try {
        $file = if ($kind -eq 'done') { 'Windows Notify System Generic.wav' } else { 'Windows Notify Calendar.wav' }
        $path = Join-Path $env:WINDIR "Media\$file"
        if (Test-Path -LiteralPath $path) { (New-Object System.Media.SoundPlayer $path).Play() }
        else { [System.Media.SystemSounds]::Asterisk.Play() }
    }
    catch {}
}

function Play-Sound($kind, [switch]$Force) {
    if (-not $script:sound -and -not $Force) { return }
    $script:lastSoundKind = $kind
    $file = if ($kind -eq 'done') { $SoundDone } else { $SoundAttention }
    if (-not [System.IO.File]::Exists($file)) { Play-WindowsSound $kind; return }
    try {
        $script:player.Stop()
        $script:player.Open((New-Object System.Uri($file)))
        $script:player.Volume = $SoundVolume
        $script:player.Play()
    }
    catch { Log "suara: $_"; Play-WindowsSound $kind }
}

function Set-Hidden([bool]$hidden) {
    if ($hidden -eq $script:hiddenForFullscreen) { return }
    $script:hiddenForFullscreen = $hidden
    # Visibility Hidden = tidak dirender sama sekali (Opacity 0 tetap memakan CPU).
    # Aman karena jendela dijalankan dengan Show() + Dispatcher.Run(), bukan ShowDialog()
    # (di ShowDialog, menyembunyikan jendela = menutup aplikasi).
    $win.Visibility = if ($hidden) { 'Hidden' } else { 'Visible' }
    if ($hidden) { Log "disembunyikan: fullscreen terdeteksi $([IslandNative]::LastFullscreenWindow)" }
    else { Log 'ditampilkan lagi' }
}

function Show-Notif($kind, $title, $project, $body, $sess) {
    $script:notif = @{
        kind = $kind; title = $title; project = $project; body = $body
        term = $sess.term; cwd = $sess.cwd; distro = $sess.distro
    }
    $script:notifUntil = [datetime]::Now.AddSeconds([double]$cfg.notifySeconds)
    Set-Hidden $false
    Play-Sound $kind
    Expand
}

function Dismiss-Notif {
    $script:notif = $null
    foreach ($s in $script:sessions.Values) { if ($s.state -eq 'done') { $s.state = 'idle' } }
    if ($script:hover) { Expand } else { Collapse }
}

# --- event dari WSL ----------------------------------------------------------
function Handle-Event($e) {
    $id = [string]$e.session
    $proj = if ($e.project) { [string]$e.project } else { 'claude' }
    if (-not $script:sessions.ContainsKey($id)) {
        $script:sessions[$id] = @{ project = $proj; state = 'idle'; ts = [datetime]::Now }
    }
    $s = $script:sessions[$id]
    $s.ts = [datetime]::Now; $s.project = $proj
    if ($e.cwd) { $s.cwd = [string]$e.cwd; $s.distro = [string]$e.distro; $s.term = [string]$e.term }

    switch ($e.event) {
        'SessionStart' { $s.state = 'idle' }
        'UserPromptSubmit' { $s.state = 'working'; $s.activity = 'think' }
        # Event alat sering sekali: cukup perbarui maskot, panel dibangun ulang belakangan.
        'PreToolUse' { $s.state = 'working'; $s.activity = 'tool'; Update-Compact; return }
        'PostToolUse' {
            $wasAttention = $s.state -eq 'attention'
            $s.state = 'working'; $s.activity = 'think'
            if (-not $wasAttention) { Update-Compact; return }
        }
        'PostToolUseFailure' {
            $s.state = 'working'; $s.activity = 'think'
            $script:errorFlashUntil = [datetime]::Now.AddSeconds(2)   # maskot "error" sekilas
            Update-Compact; return
        }
        'Stop' {
            $s.state = 'done'; $s.activity = $null
            Show-Notif 'done' 'Claude selesai' $proj ([string]$e.message) $s
            return
        }
        'StopFailure' {
            $s.state = 'idle'; $s.activity = $null
            $msg = if ($e.message) { [string]$e.message } else { 'Terjadi error saat Claude menjawab (mis. batas pemakaian atau gangguan API).' }
            Show-Notif 'error' 'Claude gagal' $proj $msg $s
            return
        }
        'Notification' {
            if ($e.type -eq 'idle_prompt') { return }   # sudah diwakili notifikasi "selesai"
            $s.state = 'attention'
            $title = if ($e.type -eq 'permission_prompt') { 'Claude butuh izin' } else { 'Claude butuh perhatian' }
            Show-Notif 'attention' $title $proj ([string]$e.message) $s
            return
        }
        'SessionEnd' { $script:sessions.Remove($id) }
    }
    Refresh-UI
}

function Read-Events {
    # Cek ukuran file dulu (murah); file baru dibuka bila ada isi baru.
    $f = $script:evFile
    $f.Refresh()
    if (-not $f.Exists) { return }
    if ($f.Length -lt $script:evOffset) { $script:evOffset = 0 }   # file dirotasi
    if ($f.Length -eq $script:evOffset) { return }

    $fs = [System.IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite, Delete')
    try {
        $len = $fs.Length - $script:evOffset
        if ($len -le 0) { return }
        [void]$fs.Seek($script:evOffset, 'Begin')
        $buf = New-Object byte[] $len
        $n = $fs.Read($buf, 0, $len)
    }
    finally { $fs.Dispose() }

    $end = [Array]::LastIndexOf($buf, [byte]10, $n - 1)   # hanya baris lengkap
    if ($end -lt 0) { return }
    $script:evOffset += $end + 1
    $text = [Text.Encoding]::UTF8.GetString($buf, 0, $end)
    foreach ($line in $text -split "`n") {
        if (-not $line.Trim()) { continue }
        try { Handle-Event ($line | ConvertFrom-Json) } catch { Log "event gagal diproses: $_ @ $($_.InvocationInfo.ScriptLineNumber) | $line" }
    }
}

# --- kuota (API usage OAuth, sama seperti /usage) ----------------------------
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$script:http = New-Object System.Net.Http.HttpClient
$script:http.Timeout = [TimeSpan]::FromSeconds(20)

function Get-Token {
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    # Token disimpan di memori; file kredensial WSL hanya dibaca saat perlu,
    # supaya VM WSL tidak terus-terusan dibangunkan.
    if ($script:forceToken -or -not $script:token -or $nowMs -gt ($script:tokenExp - 60000)) {
        $c = [System.IO.File]::ReadAllText($cfg.credentialsPath) | ConvertFrom-Json
        $script:token = $c.claudeAiOauth.accessToken
        $script:tokenExp = [double]$c.claudeAiOauth.expiresAt
        $script:forceToken = $false
    }
    $script:token
}

function Read-UsageFile {
    if (-not [System.IO.File]::Exists($UsagePath)) { return }
    $t = [System.IO.File]::GetLastWriteTimeUtc($UsagePath)
    if ($t -eq $script:usageFileTime) { return }
    $script:usageFileTime = $t
    try { $u = [System.IO.File]::ReadAllText($UsagePath) | ConvertFrom-Json } catch { return }
    $at = [DateTimeOffset]::FromUnixTimeMilliseconds([long]([double]$u.ts * 1000)).LocalDateTime
    if ($script:usageAt -and $at -le $script:usageAt) { return }   # data API lebih baru
    $script:usage = $u
    $script:usageAt = $at
    $script:usageSource = 'Claude Code'
    $script:usageErr = $null
    $script:usageNote = $null
    Refresh-UI
}

function Usage-IsFresh {
    $script:usageSource -eq 'Claude Code' -and $script:usageAt -and
    ([datetime]::Now - $script:usageAt).TotalMinutes -lt $FreshMinutes
}

function Start-UsageFetch {
    if ($script:usageTask) { return }
    $script:nextUsage = [datetime]::Now.AddSeconds($PollSeconds)
    if (-not $UseApiFallback) { $script:forceApi = $false; return }   # token tidak pernah dibaca
    if (-not $script:forceApi -and (Usage-IsFresh)) { return }
    $script:forceApi = $false
    try { $tok = Get-Token }
    catch {
        $script:usageErr = 'Kredensial tidak terbaca - pastikan WSL & Claude Code sudah login'
        Log "kredensial: $_"; Refresh-UI; return
    }
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, 'https://api.anthropic.com/api/oauth/usage')
    $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $tok)
    [void]$req.Headers.TryAddWithoutValidation('anthropic-beta', 'oauth-2025-04-20')
    [void]$req.Headers.TryAddWithoutValidation('User-Agent', 'origin-island/1.0')
    $script:usageTask = $script:http.SendAsync($req)
}

function Poll-UsageTask {
    $t = $script:usageTask
    if (-not $t -or -not $t.IsCompleted) { return }
    $script:usageTask = $null
    if ($t.IsFaulted -or $t.IsCanceled) {
        $script:usageErr = 'Gagal terhubung ke server kuota'
        Log "usage: $($t.Exception)"; Refresh-UI; return
    }
    $resp = $t.Result
    $code = [int]$resp.StatusCode
    $body = $resp.Content.ReadAsStringAsync().Result
    $retryAfter = $null
    try { if ($resp.Headers.RetryAfter -and $resp.Headers.RetryAfter.Delta) { $retryAfter = $resp.Headers.RetryAfter.Delta.Value.TotalSeconds } } catch {}
    $resp.Dispose()
    switch ($code) {
        200 {
            $script:usage = $body | ConvertFrom-Json
            $script:usageAt = [datetime]::Now
            $script:usageSource = 'API'
            $script:usageErr = $null
            $script:usageNote = $null
            $script:apiBackoff = 0
        }
        401 {
            $script:usageErr = 'Token kedaluwarsa - jalankan claude di WSL sekali'
            $script:forceToken = $true
            $script:nextUsage = [datetime]::Now.AddMinutes(5)
        }
        429 {
            $script:apiBackoff = if ($script:apiBackoff -eq 0) { 5 } else { [math]::Min(30.0, $script:apiBackoff * 2.0) }
            $wait = if ($retryAfter) { [math]::Max(60.0, [double]$retryAfter) } else { $script:apiBackoff * 60 }
            $script:nextUsage = [datetime]::Now.AddSeconds($wait)
            $msg = 'Server membatasi cek kuota - coba lagi {0:HH:mm}' -f $script:nextUsage
            # Ada data lama? Tampilkan saja dengan catatan, bukan error merah.
            if ($script:usage) { $script:usageNote = $msg } else { $script:usageErr = $msg }
            Log "usage 429, tunggu $wait detik"
        }
        default {
            $script:usageErr = "Server kuota error (HTTP $code)"
            $script:nextUsage = [datetime]::Now.AddMinutes(5)
            Log "usage HTTP $code $body"
        }
    }
    Refresh-UI
}

# --- loop utama --------------------------------------------------------------
function Tick {
    $now = [datetime]::Now
    Read-Events
    Poll-UsageTask
    if (($now - $script:lastUsageCheck).TotalSeconds -ge 2) {
        $script:lastUsageCheck = $now
        Read-UsageFile
        if ($now -ge $script:nextUsage) { Start-UsageFetch }
    }

    # Maskot "error" sekilas (alat gagal) kembali normal setelah 2 detik.
    if ($script:mascotMode -eq 'error' -and $now -ge $script:errorFlashUntil -and -not ($script:notif -and $script:notif.kind -eq 'error')) { Update-Compact }

    if ($script:notif -and $now -ge $script:notifUntil -and -not $script:hover) { Dismiss-Notif }
    elseif ($script:isExpanded -and -not $script:notif -and -not $script:hover -and ($now - $script:leaveAt).TotalMilliseconds -gt 350) { Collapse }

    if (($now - $script:lastHousekeep).TotalSeconds -ge 3) {
        $script:lastHousekeep = $now
        $hwnd = Hwnd
        [IslandNative]::Top($hwnd)

        # Sembunyikan saat video/game fullscreen (kecuali ada notifikasi). Harus terdeteksi
        # 2x berturut-turut (±6 detik) supaya jendela yang muncul sesaat tidak membuatnya berkedip.
        $fs = [bool]$cfg.hideOnFullscreen -and -not $script:notif -and [IslandNative]::ForegroundIsFullscreen($hwnd)
        $script:fullscreenHits = if ($fs) { $script:fullscreenHits + 1 } else { 0 }
        Set-Hidden ($script:fullscreenHits -ge 2)

        # Buang sesi yang sudah lama tidak ada kabar (mis. terminal ditutup paksa).
        $removed = $false
        foreach ($k in @($script:sessions.Keys)) {
            $s = $script:sessions[$k]
            $maxAge = if ($s.state -eq 'working') { 120 } else { 30 }
            if (($now - $s.ts).TotalMinutes -gt $maxAge) { $script:sessions.Remove($k); $removed = $true }
        }
        if ($removed) { Refresh-UI }

        # Monitor dicabut/dipasang atau monitor utama berganti -> atur ulang posisi.
        $sig = Screen-Signature
        if ($sig -ne $script:screenSig) { $script:screenSig = $sig; Place-Island }

        # Tanda hidup untuk launcher di WSL (supaya tidak menyalakan dobel).
        try { [System.IO.File]::WriteAllText($AlivePath, [string]$now.Ticks) } catch {}

        # Ikut berhenti bila WSL dimatikan. Cek proses itu mahal (menelusuri semua proses),
        # jadi cukup tiap 15 detik.
        if ($ExitWhenWslStops -and ($now - $script:lastWslCheck).TotalSeconds -ge 15) {
            $script:lastWslCheck = $now
            if (Wsl-IsRunning) { $script:wslDownSince = $null }
            elseif (-not $script:wslDownSince) { $script:wslDownSince = $now }
            elseif (($now - $script:wslDownSince).TotalSeconds -gt 30) { Log 'WSL berhenti, keluar'; $win.Close() }
        }

        # Siapkan isi panel di belakang layar supaya hover terasa instan.
        if (-not $script:isExpanded -and $script:expandedDirty) { Ensure-Expanded }

        # Rapikan memori sesekali saat pil sedang diam.
        if (-not $script:isExpanded -and ($now - $script:lastTrim).TotalMinutes -ge 2) {
            $script:lastTrim = $now
            [IslandNative]::Trim()
        }
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$timer.Interval = [TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({ try { Tick } catch { Log "tick: $_ $($_.ScriptStackTrace)" } })

# Sudut lengkung: kapsul ringkas = setengah lingkaran pas di ujung (radius = setengah tinggi);
# saat membesar, radius berhenti di $MaxRadius supaya tidak terlalu bulat (seperti iPhone).
# Radius lebih besar dari setengah tinggi membuat WPF menggambar ujung lonjong, jadi dibatasi.
$MaxRadius = 22.0
$Pill.Add_SizeChanged({
        $r = [math]::Min($MaxRadius, $Pill.ActualHeight / 2.0)
        if ($Pill.CornerRadius.TopLeft -ne $r) { $Pill.CornerRadius = New-Object System.Windows.CornerRadius($r) }
    })

# Semua handler mouse dibungkus try/catch: error di sini tidak boleh mematikan island.
$Island.Add_MouseEnter({ try { $script:hover = $true; if (-not $script:isExpanded) { Expand } } catch { Log "hover: $_ @ $($_.InvocationInfo.ScriptLineNumber)" } })
$Island.Add_MouseLeave({ $script:hover = $false; $script:leaveAt = [datetime]::Now })
# Seret kiri/kanan untuk memindahkan; klik tanpa geser = buka terminal terkait.
$Island.Add_MouseLeftButtonDown({ try { Drag-Start } catch { Log "seret mulai: $_ @ $($_.InvocationInfo.ScriptLineNumber)" } })
$Island.Add_MouseMove({ if ($script:drag) { try { Drag-Move } catch { Log "seret: $_ @ $($_.InvocationInfo.ScriptLineNumber)" } } })
$Island.Add_MouseLeftButtonUp({ try { Drag-End } catch { Log "seret selesai: $_ @ $($_.InvocationInfo.ScriptLineNumber)" } })
$Island.Add_LostMouseCapture({ if ($script:drag) { try { Drag-End } catch { Log "seret batal: $_" } } })

# Tombol X: abu-abu -> merah saat disorot -> merah lebih pekat saat ditekan.
$CloseIcon = New-Icon 'exit' 18 '#8E8E93'
$CloseIcon.HorizontalAlignment = 'Center'; $CloseIcon.VerticalAlignment = 'Center'
$CloseBtn.Child = $CloseIcon
$CloseBtn.Cursor = 'Hand'
$CloseBtn.Add_MouseEnter({ Set-IconColor $CloseIcon $C.Red; $CloseBtn.Background = Brush '#26FF453A' })
$CloseBtn.Add_MouseLeave({ Set-IconColor $CloseIcon '#8E8E93'; $CloseBtn.Background = Brush '#00000000' })
$CloseBtn.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Set-IconColor $CloseIcon '#FF6961'; $CloseBtn.Background = Brush '#59FF453A' })
$CloseBtn.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Log 'ditutup lewat tombol X'; $win.Close() })

$win.Add_SourceInitialized({ [IslandNative]::Setup((Hwnd)) })
$win.Add_Loaded({
        $script:screenSig = Screen-Signature
        Place-Island
        try { [System.IO.File]::WriteAllText($AlivePath, [string][datetime]::Now.Ticks) } catch {}
        Read-UsageFile
        Update-Compact
        $timer.Start()
    })
$win.Add_Closed({
        try { $timer.Stop(); $script:http.Dispose() } catch {}
        try { $script:mutex.ReleaseMutex() } catch {}
        Remove-Item -LiteralPath $AlivePath -ErrorAction SilentlyContinue
        $win.Dispatcher.InvokeShutdown()   # akhiri Dispatcher.Run() di bawah
    })

# Jaring pengaman: error WPF yang tidak tertangkap dicatat dan diabaikan, bukan mematikan island.
$win.Dispatcher.Add_UnhandledException({
        param($s, $e)
        Log "error tak tertangkap: $($e.Exception.GetType().Name): $($e.Exception.Message)"
        $e.Handled = $true
    })

Log 'Origin Island dimulai'
# Show() + Dispatcher.Run(): aplikasi hanya berhenti saat jendela benar-benar ditutup
# (tombol X / WSL berhenti), tidak ikut berhenti saat jendela disembunyikan.
try { $win.Show(); [System.Windows.Threading.Dispatcher]::Run() }
catch { Log "island berhenti karena error: $_ @ $($_.InvocationInfo.ScriptLineNumber)" }
Log 'Origin Island berhenti'
