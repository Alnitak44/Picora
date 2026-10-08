param([int]$ProxyPort = 7890)
$ErrorActionPreference = 'Stop'
$picoraRoot = Split-Path -Parent $PSScriptRoot
$picoraTools = Join-Path $picoraRoot '.tooling'
$env:ANDROID_HOME = Join-Path $picoraTools 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_USER_HOME = Join-Path $picoraTools 'android-user'
$env:GRADLE_USER_HOME = Join-Path $picoraTools 'gradle-cache'
$env:PUB_CACHE = Join-Path $picoraTools 'pub-cache'
$env:TMP = Join-Path $picoraTools 'tmp'
$env:TEMP = $env:TMP
$picoraLocalJava = Join-Path $picoraTools 'jdk/bin/java.exe'
if (Test-Path -LiteralPath $picoraLocalJava) {
    $env:JAVA_HOME = Join-Path $picoraTools 'jdk'
} elseif (-not $env:JAVA_HOME -or -not (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin/java.exe'))) {
    $picoraJava = Get-Command java.exe -ErrorAction Stop
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $picoraJava.Source)
}
if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = 'https://pub.dev' }
if (-not $env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn' }
if ($ProxyPort -gt 0) {
    $env:HTTP_PROXY = 'http://127.0.0.1:' + $ProxyPort
    $env:HTTPS_PROXY = $env:HTTP_PROXY
    $env:NO_PROXY = 'localhost,127.0.0.1,::1'
}
New-Item -ItemType Directory -Force -Path (Join-Path $picoraRoot 'artifacts') | Out-Null
foreach ($picoraPath in @($env:ANDROID_USER_HOME, $env:GRADLE_USER_HOME, $env:PUB_CACHE, $env:TMP)) {
    New-Item -ItemType Directory -Force -Path $picoraPath | Out-Null
}
$picoraInit = Join-Path $env:GRADLE_USER_HOME 'init.d'
New-Item -ItemType Directory -Force -Path $picoraInit | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'gradle-repositories.gradle') -Destination (Join-Path $picoraInit 'picora-repositories.gradle') -Force
$env:PATH = (Join-Path $picoraTools 'git/cmd') + ';' + (Join-Path $env:JAVA_HOME 'bin') + ';' + (Join-Path $env:ANDROID_HOME 'platform-tools') + ';' + (Join-Path $env:ANDROID_HOME 'cmdline-tools/latest/bin') + ';' + (Join-Path $picoraTools 'flutter/bin') + ';' + $env:PATH
