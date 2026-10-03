[CmdletBinding()]
param(
    [string]$IndexPath = (Join-Path $PSScriptRoot 'fonts_index.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'fonts_mirror_index.json'),
    [string]$ReleaseTag = 'v0.1.0',
    [int]$TimeoutSec = 120,
    [string]$GitHubToken = $env:GITHUB_TOKEN
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
    throw "Index file not found: $IndexPath"
}

$index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json
$headers = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'typst-fonts-mirror'
}
if (-not [string]::IsNullOrWhiteSpace($GitHubToken)) {
    $headers.Authorization = "Bearer $GitHubToken"
}

$releaseUri = "https://api.github.com/repos/Mapaor/typst-fonts-mirror/releases/tags/$ReleaseTag"
$release = Invoke-RestMethod `
    -Uri $releaseUri `
    -Headers $headers `
    -TimeoutSec $TimeoutSec

$assetsByName = @{}
foreach ($asset in @($release.assets)) {
    $assetsByName[$asset.name] = $asset
}

$mirrorFonts = foreach ($font in @($index.fonts)) {
    if ([string]::IsNullOrWhiteSpace($font.mirror_download_url)) {
        throw "Font '$($font.id)' is missing mirror_download_url."
    }

    $assetName = ([Uri]$font.mirror_download_url).Segments[-1]
    if (-not $assetsByName.ContainsKey($assetName)) {
        throw "Release '$ReleaseTag' is missing asset '$assetName' for font '$($font.id)'."
    }

    $asset = $assetsByName[$assetName]
    $digest = [string]$asset.digest
    if ($digest -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        throw "Asset '$assetName' has no SHA-256 digest in the GitHub API response."
    }
    if ($null -eq $asset.size -or $null -eq $asset.updated_at) {
        throw "Asset '$assetName' is missing size or updated_at in the GitHub API response."
    }

    [ordered]@{
        id = $font.id
        asset_url = $asset.browser_download_url
        file_format = $font.file_format
        asset_sha256 = $digest.Substring(7).ToLowerInvariant()
        asset_size_bytes = [long]$asset.size
        asset_last_updated = $asset.updated_at
    }
}

$output = [ordered]@{
    schema_version = 1
    release = $release.tag_name
    release_last_updated = $release.updated_at
    fonts = @($mirrorFonts)
}

$output | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Output "Generated $OutputPath with $(@($mirrorFonts).Count) fonts from release $($release.tag_name)."
