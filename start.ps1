param([switch]$Test, [switch]$Build)
$ErrorActionPreference = "Stop"
if (-not (Get-Command bal -ErrorAction SilentlyContinue)) { throw "Install Ballerina Swan Lake 2201.13.6 and restart your terminal." }
$runtimeDir = Join-Path $PSScriptRoot ".runtime"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
$env:JAVA_TOOL_OPTIONS = "$previousJavaOptions -Duser.home=$runtimeDir"
$projectDir = Join-Path $PSScriptRoot "backend/src"
$manifestPath = Join-Path $projectDir "Ballerina.toml"
$originalManifest = [IO.File]::ReadAllText($manifestPath)
$dependencyPath = Join-Path $projectDir "Dependencies.toml"
$originalDependencies = if (Test-Path -LiteralPath $dependencyPath) { [IO.File]::ReadAllText($dependencyPath) } else { $null }
Push-Location $projectDir
try {
    $useLocal = & (Join-Path $PSScriptRoot "prepare-runtime.ps1") -RuntimeDir $runtimeDir
    if ($useLocal) {
        $override = @'

[[dependency]]
org = "ballerina"
name = "http"
version = "2.17.0"
repository = "local"
'@
        [IO.File]::WriteAllText($manifestPath, $originalManifest + $override)
    }
    try {
        $ErrorActionPreference = "Continue"
        if ($Test) { $output = @(& bal test --offline 2>&1) } else { $output = @(& bal build --offline 2>&1) }
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = "Stop"
        $output | ForEach-Object { Write-Host "$_" }
        if ($exitCode -ne 0 -or ($output -match '^(error:|ERROR \[|ballerina:)')) { throw "Ballerina failed. See the output above." }
    } finally {
        [IO.File]::WriteAllText($manifestPath, $originalManifest)
        if ($useLocal) {
            if ($null -ne $originalDependencies) { [IO.File]::WriteAllText($dependencyPath, $originalDependencies) }
            elseif (Test-Path -LiteralPath $dependencyPath) { Remove-Item -LiteralPath $dependencyPath }
        }
    }
    if (-not $Test -and -not $Build) {
        Write-Host "RescuePulse: http://localhost:8080 (Ctrl+C to stop)"
        $ErrorActionPreference = "Continue"
        & java -jar target/bin/backend.jar
        $ErrorActionPreference = "Stop"
        if ($LASTEXITCODE -ne 0) { throw "RescuePulse stopped with an error." }
    }
} finally { Pop-Location; $env:JAVA_TOOL_OPTIONS = $previousJavaOptions }
