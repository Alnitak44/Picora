param(
    [switch]$MappedWorkspace,
    [ValidateSet('debug', 'release')][string]$BuildType = 'debug'
)
$ErrorActionPreference = 'Stop'
$picoraRoot = Split-Path -Parent $PSScriptRoot
if (-not $MappedWorkspace -and $picoraRoot -match '[^\x00-\x7F]') {
    $picoraDrive = @('P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z') |
        Where-Object { -not (Test-Path ($_ + ':\')) } | Select-Object -First 1
    if (-not $picoraDrive) { throw 'No free drive letter for the Android build.' }
    & subst.exe ($picoraDrive + ':') $picoraRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the temporary build drive.' }
    try {
        $picoraMappedScript = $picoraDrive + ':\scripts\build-debug.ps1'
        & $picoraMappedScript -MappedWorkspace -BuildType $BuildType
    } finally {
        # Restore dependency paths before removing our temporary drive alias.
        . (Join-Path $PSScriptRoot 'android-env.ps1')
        & (Join-Path $picoraRoot 'android/gradlew.bat') --stop | Out-Null
        Push-Location $picoraRoot
        try {
            & (Join-Path $picoraRoot '.tooling/flutter/bin/flutter.bat') pub get --offline `
                *> (Join-Path $picoraRoot 'artifacts/build-path-restore.log')
            if ($LASTEXITCODE -ne 0) {
                Write-Warning 'Restore dependency paths with flutter pub get before further development.'
            }
            $picoraLocalProperties = Join-Path $picoraRoot 'android/local.properties'
            if (Test-Path $picoraLocalProperties) {
                $picoraSdkPaths = @{
                    'flutter.sdk' = Join-Path $picoraRoot '.tooling/flutter'
                    'sdk.dir' = $env:ANDROID_HOME
                }
                $picoraPropertyLines = Get-Content -LiteralPath $picoraLocalProperties
                foreach ($picoraProperty in $picoraSdkPaths.Keys) {
                    $picoraValue = $picoraSdkPaths[$picoraProperty].Replace('\', '\\')
                    $picoraValue = [regex]::Replace($picoraValue, '[^\x00-\x7F]', {
                        param($picoraMatch)
                        '\u{0:x4}' -f [int][char]$picoraMatch.Value
                    })
                    $picoraPropertyPattern = '^' + [regex]::Escape($picoraProperty) + '='
                    $picoraPropertyLines = $picoraPropertyLines | ForEach-Object {
                        if ($_ -match $picoraPropertyPattern) { $picoraProperty + '=' + $picoraValue }
                        else { $_ }
                    }
                }
                [IO.File]::WriteAllLines($picoraLocalProperties, [string[]]$picoraPropertyLines, [Text.UTF8Encoding]::new($false))
            }
        } finally {
            Pop-Location
            & subst.exe ($picoraDrive + ':') /D
        }
    }
    return
}
. (Join-Path $PSScriptRoot 'android-env.ps1')
Push-Location $picoraRoot
try {
    if ($MappedWorkspace) {
        & (Join-Path $picoraRoot '.tooling/flutter/bin/flutter.bat') pub get --offline
        if ($LASTEXITCODE -ne 0) { throw 'Could not prepare dependencies for the build drive.' }
    }
    $picoraArgs = @('build', 'apk', ('--' + $BuildType), '--no-pub',
        '--target-platform', 'android-arm64', '--split-per-abi')
    & (Join-Path $picoraRoot '.tooling/flutter/bin/flutter.bat') @picoraArgs
    if ($LASTEXITCODE -ne 0) { throw ('Picora ' + $BuildType + ' APK build failed.') }
    $picoraOutput = Join-Path $picoraRoot 'build/app/outputs/flutter-apk'
    $picoraRelease = Join-Path $picoraRoot 'releases'
    New-Item -ItemType Directory -Force -Path $picoraRelease | Out-Null
    $picoraPackages = @(Get-Item -LiteralPath (Join-Path $picoraOutput ("app-arm64-v8a-" + $BuildType + ".apk")))
    foreach ($picoraPackage in $picoraPackages) {
        $picoraName = ("Picora-arm64-" + $BuildType + ".apk")
        $picoraTarget = Join-Path $picoraRelease $picoraName
        Copy-Item -LiteralPath $picoraPackage.FullName -Destination $picoraTarget -Force
        Get-FileHash -LiteralPath $picoraTarget -Algorithm SHA256
    }
} finally { Pop-Location }
