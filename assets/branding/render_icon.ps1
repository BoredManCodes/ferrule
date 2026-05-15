# Renders the Ferrule launcher icon (1024x1024 PNG) from primitives.
# Run from the repo root:
#   powershell -ExecutionPolicy Bypass -File assets/branding/render_icon.ps1

Add-Type -AssemblyName System.Drawing

$size   = 1024
$bmp    = New-Object System.Drawing.Bitmap $size, $size
$g      = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

function New-RoundedRectPath {
    param([float]$x, [float]$y, [float]$w, [float]$h, [float]$r)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $path.AddArc($x,         $y,         $d, $d, 180, 90)
    $path.AddArc($x+$w-$d,   $y,         $d, $d, 270, 90)
    $path.AddArc($x+$w-$d,   $y+$h-$d,   $d, $d,   0, 90)
    $path.AddArc($x,         $y+$h-$d,   $d, $d,  90, 90)
    $path.CloseFigure()
    return $path
}

# ---- Background: rounded square with vertical gradient ----
$bgPath = New-RoundedRectPath 0 0 $size $size 224
$bgRect = New-Object System.Drawing.RectangleF 0, 0, $size, $size
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $bgRect,
    [System.Drawing.Color]::FromArgb(255, 79, 70, 229),    # #4F46E5
    [System.Drawing.Color]::FromArgb(255, 49, 46, 129),    # #312E81
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
)
$g.FillPath($bgBrush, $bgPath)

# ---- White F monogram ----
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)

# shaft
$shaftPath = New-RoundedRectPath 320 208 160 640 24
$g.FillPath($white, $shaftPath)

# top arm
$topPath = New-RoundedRectPath 320 208 440 140 24
$g.FillPath($white, $topPath)

# middle arm
$midPath = New-RoundedRectPath 320 470 320 120 20
$g.FillPath($white, $midPath)

# ---- Ferrule band: copper-amber, wrapping the shaft below the top arm ----
$bandRect = New-Object System.Drawing.RectangleF 260, 372, 280, 78
$bandBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $bandRect,
    [System.Drawing.Color]::FromArgb(255, 251, 191, 36),   # #FBBF24 top
    [System.Drawing.Color]::FromArgb(255, 180,  83,   9),  # #B45309 bottom
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
)
$bandPath = New-RoundedRectPath 260 372 280 78 14
$g.FillPath($bandBrush, $bandPath)

# upper highlight strip on band (subtle sheen)
$hiRect = New-Object System.Drawing.RectangleF 266, 378, 268, 28
$hiBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $hiRect,
    [System.Drawing.Color]::FromArgb(217, 253, 230, 138),  # #FDE68A 85%
    [System.Drawing.Color]::FromArgb(  0, 253, 230, 138),  # 0%
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
)
$hiPath = New-RoundedRectPath 266 378 268 28 10
$g.FillPath($hiBrush, $hiPath)

# two thin etched grooves
$grooveBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(140, 146, 64, 14))
$g.FillRectangle($grooveBrush, 260, 392, 280, 3)
$g.FillRectangle($grooveBrush, 260, 426, 280, 3)

$out = Join-Path (Split-Path $PSScriptRoot -Parent) "icon\icon.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose()
$bmp.Dispose()
Write-Host "Wrote $out"

# ---- Adaptive foreground (transparent bg, scaled into safe area) ----
# Android adaptive icons crop the foreground to ~66% of the canvas, so the
# design needs to live inside the inner 672x672 region of a 1024x1024 image.
$fg = New-Object System.Drawing.Bitmap $size, $size
$fgG = [System.Drawing.Graphics]::FromImage($fg)
$fgG.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$fgG.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$fgG.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$fgG.Clear([System.Drawing.Color]::Transparent)

# scale 0.66 around centre (512,512); design canvas is 1024
$fgG.TranslateTransform(512.0, 512.0)
$fgG.ScaleTransform(0.66, 0.66)
$fgG.TranslateTransform(-512.0, -512.0)

# F shaft / arms
$fgG.FillPath($white, (New-RoundedRectPath 320 208 160 640 24))
$fgG.FillPath($white, (New-RoundedRectPath 320 208 440 140 24))
$fgG.FillPath($white, (New-RoundedRectPath 320 470 320 120 20))

# band
$fgG.FillPath($bandBrush, (New-RoundedRectPath 260 372 280 78 14))
$fgG.FillPath($hiBrush,   (New-RoundedRectPath 266 378 268 28 10))
$fgG.FillRectangle($grooveBrush, 260, 392, 280, 3)
$fgG.FillRectangle($grooveBrush, 260, 426, 280, 3)

$fgOut = Join-Path (Split-Path $PSScriptRoot -Parent) "icon\icon_foreground.png"
$fg.Save($fgOut, [System.Drawing.Imaging.ImageFormat]::Png)
$fgG.Dispose()
$fg.Dispose()
Write-Host "Wrote $fgOut"
