# =============================================================================
#  设计预览台 → 截图
# =============================================================================
#
#  改完 design/preview.html 之后跑一下，把七个界面各切一张图到 design/shots/。
#  用来在改 SwiftUI 之前，先把视觉确认掉（Windows 上编译不了 SwiftUI，
#  但 HTML 是能看的）。
#
#  用法：
#      powershell -File val-shop-ios/design/shoot.ps1
#      powershell -File val-shop-ios/design/shoot.ps1 -Zoom 1     # 1:1，快一点
#      （Windows PowerShell 5.1 就够；装了 pwsh 7 也一样跑）
#
#  依赖：agent-browser（npm i -g agent-browser）+ .NET 的 System.Drawing
# =============================================================================
param(
    [double]$Zoom = 2,
    [string]$Session = "ui-redesign"
)

$ErrorActionPreference = "Stop"
$env:AGENT_BROWSER_SESSION = $Session

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$root  = Split-Path -Parent $here
$out   = Join-Path $here "shots"
$page  = Join-Path $here "preview.html"
$url   = "file:///" + ($page -replace '\\', '/') -replace ' ', '%20'

New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "==> 打开 $url"
# ⚠️ `agent-browser open` 在某些环境下**启动完不返回**（浏览器明明开了，进程一直挂着），
#    直接调会把整个脚本卡死在第一行。所以用 Start-Job 起它，只等两秒就开始往下走；
#    后面每条命令仍然连在同一个 session 上，能正常用。
$null = Start-Job { param($u, $s)
    $env:AGENT_BROWSER_SESSION = $s
    agent-browser open $u 2>&1 | Out-Null
} -ArgumentList $url, $Session
Start-Sleep -Seconds 3
agent-browser wait --load networkidle *> $null

if ($Zoom -ne 1) {
    Write-Host "==> 缩放 ${Zoom}x（截图分辨率 = ${Zoom} 倍）"
    agent-browser eval "document.documentElement.style.zoom='$Zoom';'ok'" *> $null
    Start-Sleep -Milliseconds 600
}

# 每个手机壳的页内坐标 —— 从 DOM 里量，不用手算
$json = agent-browser eval "JSON.stringify([...document.querySelectorAll('.device')].map(d=>{const r=d.getBoundingClientRect();return {x:Math.round(r.x+window.scrollX),y:Math.round(r.y+window.scrollY),w:Math.round(r.width),h:Math.round(r.height)}}))" 2>$null
$json = $json.Trim('"') -replace '\\"', '"'
$rects = $json | ConvertFrom-Json

$names = @("s1-store", "s2-revealed", "s3-empty", "s4-diagnostics",
           "s5-endpoints", "s6-profile", "s7-login")

$full = Join-Path $out "page@${Zoom}x.png"
Write-Host "==> 全页截图"
agent-browser screenshot $full --full *> $null

Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile($full)
Write-Host "    全页 $($src.Width)x$($src.Height)，${Zoom}x 缩放"

for ($i = 0; $i -lt $rects.Count; $i++) {
    $r    = $rects[$i]
    $name = if ($i -lt $names.Count) { $names[$i] } else { "frame-$($i+1)" }

    $bmp = New-Object System.Drawing.Bitmap $r.w, $r.h
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($src,
        (New-Object System.Drawing.Rectangle 0, 0, $r.w, $r.h),
        (New-Object System.Drawing.Rectangle $r.x, $r.y, $r.w, $r.h),
        [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()

    $file = Join-Path $out "$name.png"
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "    ✓ $name.png  $($r.w)x$($r.h)"
}

$src.Dispose()
Write-Host "==> 完成，图在 $out"
