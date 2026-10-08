# Compile only the Android document bridge using existing cached dependencies.
# This does not invoke Gradle, Flutter build, or generate an APK.
$ErrorActionPreference = 'Stop'
$picoraRoot = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $picoraRoot '.tooling/gradle-cache/caches/modules-2/files-2.1'
function CachedJar([string]$coordinate) {
    $jar = Get-ChildItem -LiteralPath (Join-Path $cache $coordinate) -Recurse -Filter '*.jar' |
        Where-Object { $_.Name -notmatch 'sources|javadoc' } | Select-Object -First 1
    if (-not $jar) { throw "缺少缓存依赖: $coordinate" }
    return $jar.FullName
}
$compiler = @(
    'org.jetbrains.kotlin/kotlin-compiler-embeddable/2.1.0',
    'org.jetbrains.kotlin/kotlin-stdlib/2.1.0',
    'org.jetbrains.kotlin/kotlin-script-runtime/2.1.0',
    'org.jetbrains.kotlin/kotlin-reflect/1.6.10',
    'org.jetbrains.kotlin/kotlin-daemon-embeddable/2.1.0',
    'org.jetbrains.intellij.deps/trove4j/1.0.20200330',
    'org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.6.4',
    'org.jetbrains/annotations/23.0.0'
) | ForEach-Object { CachedJar $_ }
$lifecycle = @()
foreach ($group in @('androidx.lifecycle/lifecycle-common-jvm', 'androidx.lifecycle/lifecycle-common')) {
    if (-not (Test-Path -LiteralPath (Join-Path $cache $group))) { continue }
    $lifecycle += Get-ChildItem -LiteralPath (Join-Path $cache $group) -Recurse -Filter '*.jar' |
        Where-Object { $_.Name -notmatch 'sources|javadoc' } | Select-Object -ExpandProperty FullName
}
$classpath = @(
    (Join-Path $picoraRoot '.tooling/android-sdk/platforms/android-36/android.jar'),
    (CachedJar 'io.flutter/flutter_embedding_debug'),
    (CachedJar 'org.jetbrains.kotlin/kotlin-stdlib/2.1.0')
) + $lifecycle
$output = Join-Path $picoraRoot 'artifacts/kotlin-documents-check'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$arguments = @('-Dfile.encoding=UTF-8', '-cp', ($compiler -join ';'),
    'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect', '-jvm-target', '21',
    '-classpath', ($classpath -join ';'), '-d', $output,
    (Join-Path $picoraRoot 'android/app/src/main/kotlin/io/github/alnitak44/picora/MainActivity.kt'))
. (Join-Path $picoraRoot 'scripts/android-env.ps1')
& (Join-Path $env:JAVA_HOME 'bin/java.exe') @arguments
if ($LASTEXITCODE -ne 0) { throw '原生文档接口 Kotlin 编译检查失败' }
Write-Output '原生文档接口 Kotlin 编译检查通过（未生成 APK）'
