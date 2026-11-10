# Generates the SecureID launcher icon for Windows and Android.
# Run from the repository root: powershell -ExecutionPolicy Bypass -File tools/make_icon.ps1

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot

function New-RoundedRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = $r * 2
    $path.AddArc([float]$x, [float]$y, [float]$d, [float]$d, 180, 90)
    $path.AddArc([float]($x + $w - $d), [float]$y, [float]$d, [float]$d, 270, 90)
    $path.AddArc([float]($x + $w - $d), [float]($y + $h - $d), [float]$d, [float]$d, 0, 90)
    $path.AddArc([float]$x, [float]($y + $h - $d), [float]$d, [float]$d, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-IconPng([int]$Size, [bool]$Rounded, [double]$Scale) {
    $bmp = [System.Drawing.Bitmap]::new(
        $Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $rect = [System.Drawing.RectangleF]::new(0, 0, $Size, $Size)
    $from = [System.Drawing.Color]::FromArgb(255, 148, 132, 255)
    $to = [System.Drawing.Color]::FromArgb(255, 79, 63, 201)
    $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $rect, $from, $to, [float]45)

    if ($Rounded) {
        $roundedPath = New-RoundedRect 0 0 $Size $Size ($Size * 0.22)
        $g.FillPath($background, $roundedPath)
        $roundedPath.Dispose()
    } else {
        $g.FillRectangle($background, $rect)
    }
    $background.Dispose()

    $s = $Size * $Scale
    $ox = ($Size - $s) / 2
    $oy = ($Size - $s) / 2

    $shield = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $shield.AddBezier(
        [float]($ox + 0.50 * $s), [float]($oy + 0.10 * $s),
        [float]($ox + 0.64 * $s), [float]($oy + 0.16 * $s),
        [float]($ox + 0.75 * $s), [float]($oy + 0.19 * $s),
        [float]($ox + 0.83 * $s), [float]($oy + 0.22 * $s))
    $shield.AddLine(
        [float]($ox + 0.83 * $s), [float]($oy + 0.22 * $s),
        [float]($ox + 0.83 * $s), [float]($oy + 0.51 * $s))
    $shield.AddBezier(
        [float]($ox + 0.83 * $s), [float]($oy + 0.51 * $s),
        [float]($ox + 0.83 * $s), [float]($oy + 0.69 * $s),
        [float]($ox + 0.69 * $s), [float]($oy + 0.82 * $s),
        [float]($ox + 0.50 * $s), [float]($oy + 0.90 * $s))
    $shield.AddBezier(
        [float]($ox + 0.50 * $s), [float]($oy + 0.90 * $s),
        [float]($ox + 0.31 * $s), [float]($oy + 0.82 * $s),
        [float]($ox + 0.17 * $s), [float]($oy + 0.69 * $s),
        [float]($ox + 0.17 * $s), [float]($oy + 0.51 * $s))
    $shield.AddLine(
        [float]($ox + 0.17 * $s), [float]($oy + 0.51 * $s),
        [float]($ox + 0.17 * $s), [float]($oy + 0.22 * $s))
    $shield.AddBezier(
        [float]($ox + 0.17 * $s), [float]($oy + 0.22 * $s),
        [float]($ox + 0.25 * $s), [float]($oy + 0.19 * $s),
        [float]($ox + 0.36 * $s), [float]($oy + 0.16 * $s),
        [float]($ox + 0.50 * $s), [float]($oy + 0.10 * $s))
    $shield.CloseFigure()

    $white = [System.Drawing.SolidBrush]::new(
        [System.Drawing.Color]::FromArgb(255, 248, 249, 255))
    $g.FillPath($white, $shield)
    $white.Dispose()
    $shield.Dispose()

    $keyColor = [System.Drawing.Color]::FromArgb(255, 58, 45, 148)
    $keyBrush = [System.Drawing.SolidBrush]::new($keyColor)
    $g.FillEllipse(
        $keyBrush,
        [float]($ox + 0.435 * $s), [float]($oy + 0.335 * $s),
        [float](0.13 * $s), [float](0.13 * $s))
    $keyhole = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new([float]($ox + 0.463 * $s), [float]($oy + 0.415 * $s)),
        [System.Drawing.PointF]::new([float]($ox + 0.537 * $s), [float]($oy + 0.415 * $s)),
        [System.Drawing.PointF]::new([float]($ox + 0.578 * $s), [float]($oy + 0.625 * $s)),
        [System.Drawing.PointF]::new([float]($ox + 0.422 * $s), [float]($oy + 0.625 * $s))
    )
    $g.FillPolygon($keyBrush, $keyhole)
    $keyBrush.Dispose()

    $stream = [System.IO.MemoryStream]::new()
    $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $stream.ToArray()
    $stream.Dispose()
    $g.Dispose()
    $bmp.Dispose()
    return ,$bytes
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = [System.Collections.ArrayList]::new()
foreach ($size in $sizes) {
    [void]$pngs.Add((New-IconPng -Size $size -Rounded $true -Scale 1.0))
}

$icoPath = Join-Path $root 'windows\runner\resources\app_icon.ico'
$icoStream = [System.IO.MemoryStream]::new()
$writer = [System.IO.BinaryWriter]::new($icoStream)
$writer.Write([uint16]0)
$writer.Write([uint16]1)
$writer.Write([uint16]$sizes.Count)
$offset = 6 + (16 * $sizes.Count)
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $size = $sizes[$i]
    $data = [byte[]]$pngs[$i]
    $dimension = if ($size -ge 256) { 0 } else { $size }
    $writer.Write([byte]$dimension)
    $writer.Write([byte]$dimension)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$data.Length)
    $writer.Write([uint32]$offset)
    $offset += $data.Length
}
foreach ($png in $pngs) {
    $writer.Write([byte[]]$png)
}
$writer.Flush()
[System.IO.File]::WriteAllBytes($icoPath, $icoStream.ToArray())
$writer.Dispose()
$icoStream.Dispose()
Write-Output "Wrote $icoPath"

$android = [ordered]@{
    'mdpi' = 48
    'hdpi' = 72
    'xhdpi' = 96
    'xxhdpi' = 144
    'xxxhdpi' = 192
}
foreach ($entry in $android.GetEnumerator()) {
    $target = Join-Path $root "android\app\src\main\res\mipmap-$($entry.Key)\ic_launcher.png"
    $data = New-IconPng -Size $entry.Value -Rounded $false -Scale 0.80
    [System.IO.File]::WriteAllBytes($target, $data)
    Write-Output "Wrote $target"
}
