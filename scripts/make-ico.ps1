$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$projectDir = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectDir "Assets/AppIcon.png"
$outputDir = Join-Path $projectDir "Windows/Assets"
$outputPath = Join-Path $outputDir "AppIcon.ico"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$source = [System.Drawing.Image]::FromFile($sourcePath)
$bitmap = New-Object System.Drawing.Bitmap 256, 256
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.DrawImage($source, 0, 0, 256, 256)
$pngStream = New-Object System.IO.MemoryStream
$bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
$png = $pngStream.ToArray()

$file = [System.IO.File]::Create($outputPath)
$writer = New-Object System.IO.BinaryWriter $file
$writer.Write([UInt16]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]1)
$writer.Write([Byte]0)
$writer.Write([Byte]0)
$writer.Write([Byte]0)
$writer.Write([Byte]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]32)
$writer.Write([UInt32]$png.Length)
$writer.Write([UInt32]22)
$writer.Write($png)

$writer.Dispose()
$graphics.Dispose()
$bitmap.Dispose()
$source.Dispose()
$pngStream.Dispose()
