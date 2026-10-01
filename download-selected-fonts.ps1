[CmdletBinding()]
param(
    [string]$IndexPath = (Join-Path $PSScriptRoot 'fonts_index.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'fonts-selected'),
    [int]$TimeoutSec = 120,
    [switch]$Force
)

# Add font IDs from fonts_index.json here.
$FontIds = @(
    'charter'
)

$ErrorActionPreference = 'Stop'

if ($FontIds.Count -eq 0) {
    throw 'Add at least one font ID to $FontIds before running this script.'
}

if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
    throw "Index file not found: $IndexPath"
}

$index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json
$fontById = @{}
foreach ($font in @($index.fonts)) {
    $fontById[$font.id] = $font
}

$unknownFontIds = @($FontIds | Where-Object { -not $fontById.ContainsKey($_) })
if ($unknownFontIds.Count -gt 0) {
    throw "Font ID(s) not found in the index: $($unknownFontIds -join ', ')"
}

$fonts = @($FontIds | ForEach-Object { $fontById[$_] } | Where-Object {
    $_.file_format -eq 'zip' -and
    $_.download_url -notlike 'https://fonts.google.com/download?*'
})

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$downloaded = 0
$skipped = 0
$notEncountered = [System.Collections.Generic.List[string]]::new()
$googleTree = $null

function Get-GoogleFontFiles {
    param(
        [Parameter(Mandatory)]$Font,
        [Parameter(Mandatory)]$Tree
    )

    $names = @($Font.id, $Font.name) | ForEach-Object {
        ($_ -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    }

    foreach ($root in @('ofl', 'apache', 'ufl')) {
        $folder = $Tree.tree |
            Where-Object {
                $_.type -eq 'tree' -and
                $_.path.StartsWith("$root/") -and
                $names -contains ((Split-Path $_.path -Leaf) -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
            } |
            Select-Object -First 1

        if ($folder) {
            return @($Tree.tree | Where-Object {
                $_.type -eq 'blob' -and $_.path.StartsWith("$($folder.path)/")
            })
        }
    }

    return @()
}

function Test-ZipFile {
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($Path)
        return $archive.Entries.Count -gt 0
    }
    catch {
        return $false
    }
    finally {
        if ($archive) { $archive.Dispose() }
    }
}

function Save-GoogleFontArchive {
    param(
        [Parameter(Mandatory)]$Font,
        [Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    try {
        $files = @(Get-GoogleFontFiles -Font $Font -Tree $Tree)
        if ($files.Count -eq 0) {
            return $false
        }

        foreach ($file in $files) {
            $relativePath = $file.path.Substring($file.path.IndexOf('/') + 1)
            $localPath = Join-Path $temporaryDirectory $relativePath
            $localDirectory = Split-Path $localPath -Parent
            if (-not (Test-Path -LiteralPath $localDirectory)) {
                New-Item -ItemType Directory -Path $localDirectory -Force | Out-Null
            }

            Invoke-WebRequest `
                -Uri "https://raw.githubusercontent.com/google/fonts/main/$($file.path)" `
                -OutFile $localPath `
                -TimeoutSec $TimeoutSec `
                -UserAgent 'typst-fonts-mirror' `
                -UseBasicParsing
        }

        Compress-Archive -Path (Join-Path $temporaryDirectory '*') -DestinationPath $OutputPath -CompressionLevel Optimal
        return $true
    }
    finally {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$googleFonts = @($fonts | Where-Object { $_.download_url -like 'https://fonts.google.com/download?*' })
if ($googleFonts.Count -gt 0) {
    $googleTree = Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/google/fonts/git/trees/main?recursive=1' `
        -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'typst-fonts-mirror' } `
        -TimeoutSec $TimeoutSec
}

foreach ($font in $fonts) {
    if ([string]::IsNullOrWhiteSpace($font.download_url)) {
        Write-Warning "Skipping $($font.name): download_url is missing."
        continue
    }

    $outputPath = Join-Path $OutputDirectory "$($font.id).zip"
    if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
        Write-Output "SKIP  $($font.name) -> $outputPath"
        $skipped++
        continue
    }

    $temporaryPath = "$outputPath.download"
    try {
        if ($font.download_url -like 'https://fonts.google.com/download?*') {
            if (-not (Save-GoogleFontArchive -Font $font -Tree $googleTree -OutputPath $temporaryPath)) {
                $notEncountered.Add($font.name)
                Write-Warning "Skipping $($font.name): Google Fonts family was not found."
                continue
            }
        }
        else {
            Invoke-WebRequest `
                -Uri $font.download_url `
                -Method Get `
                -OutFile $temporaryPath `
                -MaximumRedirection 10 `
                -TimeoutSec $TimeoutSec `
                -UserAgent 'curl/8.9.1' `
                -UseBasicParsing
        }

        if (-not (Test-ZipFile -Path $temporaryPath)) {
            throw 'The response is not a valid non-empty ZIP archive.'
        }

        Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }

    Write-Output "DOWNLOADED $($font.name) -> $outputPath"
    $downloaded++
}

Write-Output "Downloaded $downloaded ZIP files; skipped $skipped existing files."
if ($notEncountered.Count -gt 0) {
    Write-Output "Google Fonts families not encountered: $($notEncountered -join ', ')"
}