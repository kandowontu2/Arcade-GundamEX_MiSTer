param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.5',
    [string]$QuartusDirectory = $env:QUARTUS_ROOTDIR,
    [string]$RomArchive,
    [switch]$UpdateReleaseArtifacts
)
# OpenAI Codex and kandowontu; SPDX-License-Identifier: GPL-3.0-or-later
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$QuartusDirectory) { throw 'Pass -QuartusDirectory with the installed quartus directory' }
$QuartusDirectory = (Resolve-Path -LiteralPath $QuartusDirectory).Path
$bin = Join-Path $QuartusDirectory 'bin64'
$build = Join-Path $root 'output_files'
function Invoke-Checked([string]$Executable, [string[]]$Arguments, [string]$Log) {
    & $Executable @Arguments *> $Log
    if ($LASTEXITCODE -ne 0) { throw "Command failed; inspect $Log" }
}
Push-Location $root
try {
    New-Item -ItemType Directory -Path $build -Force | Out-Null
    $top = Get-Content -LiteralPath 'GundamEX.sv' -Raw
    if (!$top.Contains('"v,' + $Version + ';"')) { throw 'OSD version differs from requested release' }
    $settings = Get-Content -LiteralPath 'GundamEX.qsf' -Raw
    if ($settings -match 'GUNDAM_SDRAM_' -or [regex]::Matches($settings, 'VERILOG_MACRO').Count -ne 1) {
        throw 'Private synthesis settings in production project'
    }
    $files = @(& git ls-files 'rtl/*' 'sys/*') +
        @('GundamEX.sv', 'GundamEX.qsf', 'GundamEX.qpf', 'GundamEX.sdc', 'files.qip', 'timing_report.tcl')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inventory fitted sources' }
    $manifest = @($files | ForEach-Object {
        [pscustomobject]@{ Path = $_; Hash = (Get-FileHash -LiteralPath $_).Hash }
    })
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $build "v$Version-fitted-source.json")
    & ./sim/run_unit_tests.ps1 -QuartusDirectory $QuartusDirectory *> (Join-Path $build "v$Version-tests.log")
    if ($LASTEXITCODE -ne 0) { throw 'Production regressions failed' }
    if ($RomArchive) {
        Invoke-Checked 'python' @('tools/verify_capture_image.py', $RomArchive, '--cross-check-compact') (Join-Path $build "v$Version-rom-oracle.log")
    }
    Write-Host "Compiling v$Version; this can take tens of minutes."
    Invoke-Checked (Join-Path $bin 'quartus_sh.exe') @('--flow', 'compile', 'GundamEX') (Join-Path $build "v$Version-build.log")
    Invoke-Checked (Join-Path $bin 'quartus_sta.exe') @('-t', 'scripts/audit_sdram_f0.tcl') (Join-Path $build 'sdram-f0-audit.log')
    Invoke-Checked (Join-Path $bin 'quartus_cpf.exe') @('-c', '-o', 'bitstream_compression=on', 'output_files/GundamEX.sof', 'output_files/Arcade-GundamEX.rbf') (Join-Path $build 'sdram-f0-convert.log')
    $rbf = Join-Path $build 'Arcade-GundamEX.rbf'
    if ((Get-FileHash -LiteralPath $rbf).Hash -ne (Get-FileHash -LiteralPath (Join-Path $build 'GundamEX.rbf')).Hash) {
        throw 'Compressed CPF and standard assembler exports differ'
    }
    foreach ($file in $manifest) {
        if ((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.Hash) { throw "Source changed during compile: $($file.Path)" }
    }
    if ($UpdateReleaseArtifacts) {
        New-Item -ItemType Directory -Path (Join-Path $root 'releases') -Force | Out-Null
        Copy-Item -LiteralPath $rbf -Destination 'releases/Arcade-GundamEX.rbf' -Force
        Copy-Item -LiteralPath 'mra/Mobile Suit Gundam EX Revue.mra' -Destination 'releases/Mobile Suit Gundam EX Revue.mra' -Force
        $lines = @(
            "{0}  _Arcade/cores/Arcade-GundamEX.rbf" -f (Get-FileHash -LiteralPath $rbf).Hash.ToLowerInvariant()
            "{0}  _Arcade/Mobile Suit Gundam EX Revue.mra" -f (Get-FileHash -LiteralPath 'releases/Mobile Suit Gundam EX Revue.mra').Hash.ToLowerInvariant()
        )
        [System.IO.File]::WriteAllText((Join-Path $root 'SHA256SUMS.txt'), ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
    }
    Write-Host 'Build/audit complete. Review timing and update docs/RELEASE_VALIDATION.md before packaging.'
} finally { Pop-Location }
