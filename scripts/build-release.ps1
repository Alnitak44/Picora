$ErrorActionPreference = 'Stop'
$picoraRoot = Split-Path -Parent $PSScriptRoot
$picoraConfig = Join-Path $picoraRoot 'android/key.properties'
if (-not (Test-Path -LiteralPath $picoraConfig -PathType Leaf)) {
    throw 'Configure android/key.properties with your release keystore first.'
}
$picoraConfiguration = [IO.File]::ReadAllText($picoraConfig)
foreach ($picoraProperty in @('storeFile', 'keyAlias', 'storePassword', 'keyPassword')) {
    if ($picoraConfiguration -notmatch ('(?m)^' + $picoraProperty + '=.+$')) {
        throw ('Missing signing property: ' + $picoraProperty)
    }
}
& (Join-Path $PSScriptRoot 'build-debug.ps1') -BuildType release
