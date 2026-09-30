# As of 2026-30-09 all links in fonts_index.json pass the check of this script.

[CmdletBinding()]
param(
    [string]$IndexPath = (Join-Path $PSScriptRoot 'fonts_index.json'),
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
    throw "Index file not found: $IndexPath"
}

$index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json
$checks = @(
    @{ Name = 'homepage_url'; GetUrl = { param($font) $font.homepage_url } },
    @{ Name = 'download_url'; GetUrl = { param($font) $font.download_url } },
    @{ Name = 'license.url'; GetUrl = { param($font) $font.license.url } },
    @{ Name = 'license.text_url'; GetUrl = { param($font) $font.license.text_url } }
)
$getMethodUrls = @(
    'https://www.brailleinstitute.org/freefont/' # Exception: this URL does not support HEAD requests, so we use GET instead
)

$results = foreach ($font in $index.fonts) {
    foreach ($check in $checks) {
        $url = & $check.GetUrl $font
        $statusCode = $null
        $reachable = $false
        $errorMessage = $null

        if ([string]::IsNullOrWhiteSpace($url)) {
            $errorMessage = 'URL is missing'
        }
        else {
            try {
                $method = if ($getMethodUrls -contains $url) { 'Get' } else { 'Head' }
                $attemptCount = if ($getMethodUrls -contains $url) { 3 } else { 1 }
                for ($attempt = 1; $attempt -le $attemptCount; $attempt++) {
                    try {
                        $response = Invoke-WebRequest `
                            -Uri $url `
                            -Method $method `
                            -MaximumRedirection 10 `
                            -TimeoutSec $TimeoutSec `
                            -UserAgent 'curl/8.9.1' `
                            -UseBasicParsing
                        break
                    }
                    catch {
                        if ($attempt -eq $attemptCount) {
                            throw
                        }
                    }
                }
                $statusCode = [int]$response.StatusCode
                $reachable = $statusCode -eq 200
                if (-not $reachable) {
                    $errorMessage = "Expected 200, received $statusCode"
                }
            }
            catch {
                $response = $_.Exception.Response
                if ($response -and $response.StatusCode) {
                    $statusCode = [int]$response.StatusCode
                }
                $errorMessage = $_.Exception.Message
            }
        }

        $result = [PSCustomObject]@{
            Font       = $font.name
            Id         = $font.id
            Link       = $check.Name
            Url        = $url
            StatusCode = $statusCode
            Reachable  = $reachable
            Error      = $errorMessage
        }

        $status = if ($result.Reachable) { 'OK  ' } else { 'FAIL' }
        $details = if ($result.Error) { " - $($result.Error)" } else { '' }
        Write-Host ("{0} {1} - {2}{3}" -f $status, $result.Font, $result.Link, $details)
        $result
    }
}

$failed = @($results | Where-Object { -not $_.Reachable })

Write-Output ''
Write-Output "Checked $($results.Count) links for $($index.fonts.Count) fonts."
Write-Output "Failed: $($failed.Count)"
Write-Output "Success: $($results.Count - $failed.Count)"
if (failed.count == 0) {
    Write-Output "All links were successful 🎉!"
}

if ($failed.Count -gt 0) {
    exit 1
}