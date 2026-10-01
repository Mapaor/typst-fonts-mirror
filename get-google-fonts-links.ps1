[CmdletBinding()]
param(
    [string]$IndexPath = (Join-Path $PSScriptRoot 'fonts_index.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'google_fonts_links.json'),
    [int]$TimeoutSec = 120
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
    throw "Index file not found: $IndexPath"
}

$index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json
$fonts = @($index.fonts | Where-Object {
    $_.download_url -like 'https://fonts.google.com/download?*'
})

$tree = Invoke-RestMethod `
    -Uri 'https://api.github.com/repos/google/fonts/git/trees/main?recursive=1' `
    -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'typst-fonts-mirror' } `
    -TimeoutSec $TimeoutSec

$results = foreach ($font in $fonts) {
    $names = @($font.id, $font.name) | ForEach-Object {
        ($_ -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    }

    $folder = $null
    foreach ($root in @('ofl', 'apache', 'ufl')) {
        $folder = $tree.tree |
            Where-Object {
                $_.type -eq 'tree' -and
                $_.path.StartsWith("$root/") -and
                $names -contains ((Split-Path $_.path -Leaf) -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
            } |
            Select-Object -First 1

        if ($folder) {
            break
        }
    }

    if (-not $folder) {
        Write-Host "`"$($font.name)`": `"Google Fonts repository family not found.`""
        [PSCustomObject]@{
            id               = $font.id
            name             = $font.name
            github_directory = $null
            download_links   = @()
            error            = 'Google Fonts repository family not found.'
        }
        continue
    }

    $links = @($tree.tree | Where-Object {
        $_.type -eq 'blob' -and
        $_.path.StartsWith("$($folder.path)/") -and
        $_.path -match '\.(ttf|otf|woff2?)$'
    } | ForEach-Object {
        "https://raw.githubusercontent.com/google/fonts/main/$($_.path)"
    })

    if ($links.Count -eq 0) {
        Write-Host "`"$($font.name)`": `"No font files found in the family directory.`""
        [PSCustomObject]@{
            id               = $font.id
            name             = $font.name
            github_directory = "https://github.com/google/fonts/tree/main/$($folder.path)"
            download_links   = @()
            error            = 'No font files found in the family directory.'
        }
        continue
    }

    $links | ForEach-Object {
        Write-Host "`"$($font.name)`": `"$_`""
    }

    [PSCustomObject]@{
        id              = $font.id
        name            = $font.name
        github_directory = "https://github.com/google/fonts/tree/main/$($folder.path)"
        download_links  = $links
        error           = $null
    }
}

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$resolved = @($results | Where-Object { $_.download_links.Count -gt 0 })
$unresolved = @($results | Where-Object { $_.download_links.Count -eq 0 })

Write-Host "Wrote $($results.Count) Google font entries to $OutputPath."
Write-Host "Resolved: $($resolved.Count)"
Write-Host "Unresolved: $($unresolved.Count)"
if ($unresolved.Count -gt 0) {
    Write-Host 'Could not resolve:'
    $unresolved | ForEach-Object {
        Write-Host "`"$($_.name)`": `"$($_.error)`""
    }
}
