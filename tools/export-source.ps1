param([switch]$Force)
# Export the current worktree, including untracked source, without modifying it.
$ErrorActionPreference = 'Stop'
$picoraRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$picoraGit = Join-Path $picoraRoot '.tooling/git/cmd/git.exe'
if (-not (Test-Path -LiteralPath $picoraGit)) {
    $picoraGit = (Get-Command git -ErrorAction Stop).Source
}
Push-Location $picoraRoot
try {
    $picoraVersionText = [IO.File]::ReadAllText((Join-Path $picoraRoot 'pubspec.yaml'))
    $picoraVersionMatch = [regex]::Match($picoraVersionText, '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$')
    if (-not $picoraVersionMatch.Success) { throw 'Cannot read the source version.' }
    $picoraVersion = $picoraVersionMatch.Groups[1].Value
    $picoraCandidates = @(& $picoraGit -c core.quotePath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot list source files; run this in the Git worktree.' }
    $picoraIgnoredTracked = @(& $picoraGit -c core.quotePath=false ls-files -ci --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect ignored tracked files.' }
    $picoraExcluded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($picoraIgnored in $picoraIgnoredTracked) { [void]$picoraExcluded.Add($picoraIgnored) }
    $picoraRows = @()
    foreach ($picoraRelative in ($picoraCandidates | Sort-Object -Unique)) {
        if ($picoraExcluded.Contains($picoraRelative)) { continue }
        $picoraPath = [IO.Path]::GetFullPath((Join-Path $picoraRoot $picoraRelative))
        if (-not $picoraPath.StartsWith($picoraRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Source path is outside the project.'
        }
        if (-not (Test-Path -LiteralPath $picoraPath -PathType Leaf)) { continue }
        $picoraInfo = Get-Item -LiteralPath $picoraPath
        if ($picoraInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Link file: $picoraRelative" }
        if ($picoraRelative -match '(^|/)(\.git|\.tooling|artifacts|build|\.dart_tool|\.gradle|\.cxx|Pods)(/|$)' -or
            $picoraRelative -match '(^|/)(key\.properties|local\.properties|\.env(?:\..*)?|flutter_export_environment\.sh)$' -or
            $picoraRelative -match '\.(apk|aab|keystore|jks|p12|pfx|log)$') {
            throw "Private or generated file in export candidates: $picoraRelative"
        }
        if ($picoraInfo.Length -ge 50MB) { throw "Large source file; review before publishing: $picoraRelative" }
        $picoraRows += [pscustomobject]@{
            path = $picoraRelative.Replace('\', '/')
            size = $picoraInfo.Length
            sha256 = (Get-FileHash -LiteralPath $picoraPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    if ($picoraRows.Count -eq 0) { throw 'No source files found.' }
    foreach ($picoraRequired in @('README.md', 'LICENSE', 'pubspec.yaml', 'pubspec.lock',
        'lib/main.dart', 'docs/PLUGINS.md', 'plugins/template/plugin.json',
        'android/gradlew', 'android/gradlew.bat', 'android/gradle/wrapper/gradle-wrapper.jar')) {
        if ($picoraRequired -notin $picoraRows.path) { throw "Required source missing: $picoraRequired" }
    }
    $picoraOutputDir = Join-Path $picoraRoot 'artifacts/github'
    [IO.Directory]::CreateDirectory($picoraOutputDir) | Out-Null
    $picoraZipPath = Join-Path $picoraOutputDir ("Picora-source-$picoraVersion.zip")
    $picoraManifestPath = Join-Path $picoraOutputDir ("Picora-source-$picoraVersion.manifest.json")
    if (-not $Force -and ((Test-Path -LiteralPath $picoraZipPath) -or (Test-Path -LiteralPath $picoraManifestPath))) {
        throw 'Export exists; use -Force only when you intend to replace it.'
    }
    $picoraPending = Join-Path $picoraOutputDir ([IO.Path]::GetRandomFileName() + '.zip')
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $picoraArchive = [IO.Compression.ZipFile]::Open($picoraPending, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($picoraRow in $picoraRows) {
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $picoraArchive, (Join-Path $picoraRoot $picoraRow.path), ('Picora/' + $picoraRow.path),
                    [IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        } finally {
            $picoraArchive.Dispose()
        }
        Move-Item -LiteralPath $picoraPending -Destination $picoraZipPath -Force:$Force
        $picoraManifest = [pscustomobject]@{
            version = $picoraVersion
            exportedAt = (Get-Date).ToString('o')
            fileCount = $picoraRows.Count
            totalBytes = ($picoraRows | Measure-Object -Property size -Sum).Sum
            zipSha256 = (Get-FileHash -LiteralPath $picoraZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            files = $picoraRows
        }
        [IO.File]::WriteAllText($picoraManifestPath, ($picoraManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    } finally {
        if (Test-Path -LiteralPath $picoraPending) { Remove-Item -LiteralPath $picoraPending }
    }
    Write-Output "Exported $($picoraRows.Count) source files: $picoraZipPath"
    Write-Output "SHA-256 manifest: $picoraManifestPath"
} finally {
    Pop-Location
}
