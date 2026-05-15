# Generates the Play Store feature graphic (1024x500 PNG) for Ferrule.
# Brand-matched to assets/branding/ferrule_logo.svg.

Add-Type -AssemblyName System.Drawing

$W = 1024
$H = 500
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.TextRenderingHint  = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# --- Background: vertical indigo gradient (#4F46E5 -> #312E81) ---
$bgRect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $bgRect,
    [System.Drawing.Color]::FromArgb(255, 0x4F, 0x46, 0xE5),
    [System.Drawing.Color]::FromArgb(255, 0x31, 0x2E, 0x81),
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
)
$g.FillRectangle($bgBrush, $bgRect)
$bgBrush.Dispose()

# Subtle radial glow behind the mark to add depth
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glowPath.AddEllipse(40, 60, 480, 380)
$glowBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
$glowBrush.CenterColor = [System.Drawing.Color]::FromArgb(70, 0x81, 0x7C, 0xFF)
$glowBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 0x4F, 0x46, 0xE5))
$g.FillPath($glowBrush, $glowPath)
$glowBrush.Dispose()
$glowPath.Dispose()

# --- Helper: rounded rectangle path ---
function New-RoundedRectPath {
    param([float]$x, [float]$y, [float]$w, [float]$h, [float]$r)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# --- F monogram + ferrule band ---
# SVG coords are 0..1024. We scale to a 360px target box and place it on the left.
$markSize = 360.0
$markX    = 80.0
$markY    = ($H - $markSize) / 2  # vertically centered
$s        = $markSize / 1024.0    # scale factor

function Add-Scaled-RoundRect {
    param($graphics, $brush, [float]$sx, [float]$sy, [float]$sw, [float]$sh, [float]$sr)
    $p = New-RoundedRectPath ($markX + $sx * $s) ($markY + $sy * $s) ($sw * $s) ($sh * $s) ($sr * $s)
    $graphics.FillPath($brush, $p)
    $p.Dispose()
}

# F shaft + top arm + middle arm (white)
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
Add-Scaled-RoundRect $g $white 320 208 160 640 24    # shaft
Add-Scaled-RoundRect $g $white 320 208 440 140 24    # top arm
Add-Scaled-RoundRect $g $white 320 470 320 120 20    # middle arm
$white.Dispose()

# Ferrule band (gold gradient)
$bandRect = New-Object System.Drawing.RectangleF (
    [single]($markX + 260 * $s),
    [single]($markY + 372 * $s),
    [single](280 * $s),
    [single](78 * $s)
)
$bandBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $bandRect,
    [System.Drawing.Color]::FromArgb(255, 0xFB, 0xBF, 0x24),
    [System.Drawing.Color]::FromArgb(255, 0xB4, 0x53, 0x09),
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
)
# Three-stop gradient: amber -> orange -> deep amber
$blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
$blend.Colors = @(
    [System.Drawing.Color]::FromArgb(255, 0xFB, 0xBF, 0x24),
    [System.Drawing.Color]::FromArgb(255, 0xD9, 0x77, 0x06),
    [System.Drawing.Color]::FromArgb(255, 0xB4, 0x53, 0x09)
)
$blend.Positions = @([single]0.0, [single]0.5, [single]1.0)
$bandBrush.InterpolationColors = $blend
$bandPath = New-RoundedRectPath $bandRect.X $bandRect.Y $bandRect.Width $bandRect.Height (14 * $s)
$g.FillPath($bandBrush, $bandPath)
$bandBrush.Dispose()
$bandPath.Dispose()

# Band highlight strip (light yellow, fading)
$hiRect = New-Object System.Drawing.RectangleF (
    [single]($markX + 266 * $s),
    [single]($markY + 378 * $s),
    [single](268 * $s),
    [single](28 * $s)
)
$hiBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $hiRect,
    [System.Drawing.Color]::FromArgb(217, 0xFD, 0xE6, 0x8A),
    [System.Drawing.Color]::FromArgb(0,   0xFD, 0xE6, 0x8A),
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
)
$hiPath = New-RoundedRectPath $hiRect.X $hiRect.Y $hiRect.Width $hiRect.Height (10 * $s)
$g.FillPath($hiBrush, $hiPath)
$hiBrush.Dispose()
$hiPath.Dispose()

# Two thin groove lines on the band
$groove = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(140, 0x92, 0x40, 0x0E))
$g.FillRectangle($groove,
    [single]($markX + 260 * $s), [single]($markY + 392 * $s),
    [single](280 * $s),          [single](3 * $s))
$g.FillRectangle($groove,
    [single]($markX + 260 * $s), [single]($markY + 426 * $s),
    [single](280 * $s),          [single](3 * $s))
$groove.Dispose()

# --- Wordmark + tagline ---
$textX = 490
$wordmarkFont = New-Object System.Drawing.Font("Segoe UI", 92, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$taglineFont  = New-Object System.Drawing.Font("Segoe UI", 34, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$smallFont    = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$whiteBrush  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$softBrush   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230, 0xE0, 0xE7, 0xFF))
$mutedBrush  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 0xC7, 0xD2, 0xFE))

# Title
$g.DrawString("Ferrule", $wordmarkFont, $whiteBrush, [single]$textX, [single]150)

# Tagline
$g.DrawString("Client for ITFlow", $taglineFont, $softBrush, [single]$textX, [single]260)

# Small descriptor
$dot = [char]0x00B7
$g.DrawString("Tickets $dot Clients $dot Assets $dot Time", $smallFont, $mutedBrush, [single]$textX, [single]320)

# Thin gold accent bar above the tagline
$accent = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0xFB, 0xBF, 0x24))
$g.FillRectangle($accent, [single]$textX, [single]370, [single]72, [single]4)
$accent.Dispose()

$wordmarkFont.Dispose()
$taglineFont.Dispose()
$smallFont.Dispose()
$whiteBrush.Dispose()
$softBrush.Dispose()
$mutedBrush.Dispose()

# --- Save ---
$outPath = Join-Path (Get-Location) 'assets\branding\feature_graphic_1024x500.png'
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

$info = Get-Item $outPath
"$outPath  ($([math]::Round($info.Length/1KB,1)) KB)"
