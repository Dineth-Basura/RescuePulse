# Rebuild installed HTTP source when its bundled dependency is missing.
param([Parameter(Mandatory=$true)][string]$RuntimeDir)
$ErrorActionPreference = "Stop"
$distribution = Join-Path $env:ProgramFiles "Ballerina/distributions/ballerina-2201.13.6"
$httpSource = Join-Path $distribution "repo/bala/ballerina/http/2.17.0/java21"
if (-not (Test-Path -LiteralPath $httpSource)) { return $false }
$graph = Get-Content (Join-Path $httpSource "dependency-graph.json") -Raw | ConvertFrom-Json
$jsonDependency = $graph.packages | Where-Object { $_.name -eq "data.jsondata" } | Select-Object -First 1
if (-not $jsonDependency) { return $false }
$required = Join-Path $distribution ("repo/bala/ballerina/data.jsondata/" + $jsonDependency.version)
if (Test-Path -LiteralPath $required) { return $false }
$localPackage = Join-Path $RuntimeDir ".ballerina/repositories/local/bala/ballerina/http/2.17.0/java21"
if (Test-Path -LiteralPath (Join-Path $localPackage "package.json")) { return $true }
Write-Host "Rebuilding bundled Ballerina HTTP source for installed offline dependencies..."
$sourceDir = Join-Path $RuntimeDir "http-source"
New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
$modulesDir = Join-Path $httpSource "modules"
foreach ($module in Get-ChildItem -LiteralPath $modulesDir -Directory) {
    $target = $sourceDir
    if ($module.Name -ne "http") { $target = Join-Path $sourceDir ("modules/" + $module.Name.Substring(5)) }
    foreach ($source in Get-ChildItem -LiteralPath $module.FullName -Recurse -File) {
        if ($source.Extension -eq ".md") { continue }
        $relative = $source.FullName.Substring($module.FullName.Length + 1)
        $destination = Join-Path $target $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
    }
}
$manifest = @'
[package]
org = "ballerina"
name = "http"
version = "2.17.0"
distribution = "2201.13.6"
'@
$metadata = Get-Content (Join-Path $httpSource "package.json") -Raw | ConvertFrom-Json
foreach ($dependency in $metadata.platformDependencies) {
    $jar = (Join-Path $httpSource $dependency.path).Replace('\','/')
    $manifest += "`n[[platform.java21.dependency]]`npath = `"$jar`"`n"
}
[IO.File]::WriteAllText((Join-Path $sourceDir "Ballerina.toml"), $manifest)
Push-Location $sourceDir
try {
    $ErrorActionPreference = "Continue"
    $output = @(& bal pack --offline 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    $output | ForEach-Object { Write-Host "$_" }
    if ($exitCode -ne 0 -or ($output -match '^(error:|ERROR \[|ballerina:)')) { throw "Offline HTTP rebuild failed." }
} finally { Pop-Location }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $sourceDir "target/bala/ballerina-http-java21-2.17.0.bala"))
try {
    foreach ($entry in $archive.Entries) {
        if (-not $entry.Name -or $entry.FullName.EndsWith('.md')) { continue }
        $destination = [IO.Path]::GetFullPath((Join-Path $localPackage $entry.FullName))
        $safeRoot = [IO.Path]::GetFullPath($localPackage) + [IO.Path]::DirectorySeparatorChar
        if (-not $destination.StartsWith($safeRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Invalid archive path" }
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
    }
} finally { $archive.Dispose() }
return $true
