param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.5',
    [string]$OutputDirectory
)
# OpenAI Codex and kandowontu; SPDX-License-Identifier: GPL-3.0-or-later
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$OutputDirectory) { $OutputDirectory = Join-Path $root "release/v$Version" }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$build = Join-Path $root 'output_files'
$fit = Get-Content -LiteralPath (Join-Path $build 'GundamEX.fit.summary') -Raw
$flow = Get-Content -LiteralPath (Join-Path $build "v$Version-build.log") -Raw
if ($fit -notmatch 'Successful' -or $flow -notmatch 'Full Compilation was successful' -or $flow -match '(?m)^Error') {
    throw 'Production compilation did not succeed'
}
$timing = Get-Content -LiteralPath (Join-Path $build 'GundamEX.sta.summary') -Raw
foreach ($type in @('Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width')) {
    $entries = [regex]::Matches($timing, "(?m)^Type\s*:\s*$type[^\r\n]*\r?\nSlack\s*:\s*(-?[0-9.]+)")
    if (!$entries.Count) { throw "Missing $type timing results" }
    foreach ($entry in $entries) {
        if ([double]$entry.Groups[1].Value -lt 0) { throw "Negative $type internal timing" }
    }
}
$audit = Get-Content -LiteralPath (Join-Path $build 'sdram-f0-audit.log') -Raw
if ($audit -notmatch 'PASS: sixteen fixed F0 input captures' -or $audit -match '(?m)^Error') { throw 'Fitted F0 audit failed' }
$tests = Get-Content -LiteralPath (Join-Path $build "v$Version-tests.log") -Raw
if ([regex]::Matches($tests, '(?m)^[^\r\n]*PASS').Count -ne 21 -or
    $tests -match '(?im)^(FATAL:|FAIL(?:ED)?\b|Exception:)') { throw 'Production regressions did not pass' }
if ((Get-Content -LiteralPath (Join-Path $root 'docs/RELEASE_VALIDATION.md') -Raw) -match 'compile and fitted-register audit are pending') {
    throw 'Validation documentation is incomplete'
}
$manifest = Get-Content -LiteralPath (Join-Path $build "v$Version-fitted-source.json") -Raw | ConvertFrom-Json
foreach ($file in $manifest) {
    if ((Get-FileHash -LiteralPath (Join-Path $root $file.Path)).Hash -ne $file.Hash) { throw "Fitted source changed: $($file.Path)" }
}
$rbf = Join-Path $root 'releases/Arcade-GundamEX.rbf'
foreach ($copy in @('GundamEX.rbf', 'Arcade-GundamEX.rbf')) {
    if ((Get-FileHash -LiteralPath $rbf).Hash -ne (Get-FileHash -LiteralPath (Join-Path $build $copy)).Hash) {
        throw 'Release RBF must equal the standard assembler and compressed CPF exports'
    }
}
$qsf = Get-Content -LiteralPath (Join-Path $root 'GundamEX.qsf') -Raw
if ($qsf -match 'GUNDAM_SDRAM_' -or [regex]::Matches($qsf, 'VERILOG_MACRO').Count -ne 1) { throw 'Private synthesis settings' }
$mraName = 'Mobile Suit Gundam EX Revue.mra'
$zip = Join-Path $OutputDirectory "Arcade-GundamEX_MiSTer_v$Version.zip"
$sourceZip = Join-Path $OutputDirectory "Arcade-GundamEX_MiSTer_v${Version}_source.zip"
$sums = Join-Path $OutputDirectory 'SHA256SUMS.txt'
foreach ($target in @($zip, $sourceZip, $sums)) {
    if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite: $target" }
}
Push-Location $root
try {
    & python tools/verify_release.py --version $Version
    if ($LASTEXITCODE -ne 0) { throw 'Release verification failed' }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($pair in @(
            @('releases/Arcade-GundamEX.rbf', '_Arcade/cores/Arcade-GundamEX.rbf'),
            @("releases/$mraName", "_Arcade/$mraName"),
            @('RELEASE_NOTES.md', 'README.txt'), @('CREDITS.md', 'CREDITS.md'),
            @('LICENSE', 'LICENSE'), @('SHA256SUMS.txt', 'SHA256SUMS.txt')
        )) {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root $pair[0]), $pair[1]) | Out-Null
        }
    } finally { $archive.Dispose() }
    & python tools/verify_release.py --version $Version --zip $zip
    if ($LASTEXITCODE -ne 0) { throw 'ZIP payload verification failed' }
    $files = & git ls-files
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inventory source' }
    $archive = [System.IO.Compression.ZipFile]::Open($sourceZip, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            if ($file -match '^releases/' -or $file -eq 'SHA256SUMS.txt') { continue }
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root $file), $file) | Out-Null
        }
    } finally { $archive.Dispose() }
    $lines = @((Get-Content -LiteralPath (Join-Path $root 'SHA256SUMS.txt')))
    foreach ($file in @($zip, $sourceZip)) {
        $lines += "{0}  {1}" -f (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant(), (Split-Path $file -Leaf)
    }
    [System.IO.File]::WriteAllText($sums, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
    Get-FileHash -LiteralPath $zip, $sourceZip | Format-Table
} finally { Pop-Location }
