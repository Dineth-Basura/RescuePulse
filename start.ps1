param([switch]$Test, [switch]$Build)
$ErrorActionPreference = "Stop"
if (-not (Get-Command bal -ErrorAction SilentlyContinue)) { throw "Install Ballerina Swan Lake 2201.13.6 and restart your terminal." }
$runtimeDir = Join-Path $PSScriptRoot ".runtime"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
$env:JAVA_TOOL_OPTIONS = "$previousJavaOptions -Duser.home=$runtimeDir"
$projectDir = Join-Path $PSScriptRoot "backend/src"
$jarPath = Join-Path $projectDir "target/bin/backend.jar"
# Windows does not allow Ballerina to overwrite the JAR while a java -jar process holds it.
if (Test-Path -LiteralPath $jarPath) {
    try {
        $probe = [System.IO.File]::Open($jarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $probe.Dispose()
    } catch [System.IO.IOException] {
        $msg = "RescuePulse backend.jar is locked."
        try {
            $procs = Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*backend.jar*" }
            if ($procs) {
                $pids = ($procs | ForEach-Object { $_.ProcessId }) -join ", "
                $msg += " It is held by Java process ID $pids. Stop this process to continue."
            }
        } catch {}
        throw "$msg Press Ctrl+C in the running backend terminal, or stop that RescuePulse process, then retry."
    }
}
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
