param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputPath 必须以 .zip 结尾'
}
if ($output.StartsWith($source.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw '输出 ZIP 不能放进插件源码目录，否则会把自身打进压缩包'
}
$metadata = Get-Content -LiteralPath (Join-Path $source 'plugin.json') -Raw | ConvertFrom-Json
if ($metadata.packageVersion -ne 1 -or $metadata.runtime -ne 'http-v1') {
    throw '需要 packageVersion: 1 和 runtime: http-v1'
}
if (-not $metadata.entry -or $metadata.entry -match '(^/|\\|:|(^|/)\.\.?(/|$))' -or
    -not $metadata.entry.EndsWith('.json')) { throw '程序文件 entry 路径不合法' }
foreach ($name in @('readme.md', $metadata.entry)) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) {
        throw "缺少 $name"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $source 'assets') -PathType Container)) {
    throw '缺少 assets 资源目录；没有资源时也请保留空目录'
}
if ((Test-Path -LiteralPath $output) -and -not $Force) {
    throw '输出文件已存在，确认后传入 -Force 覆盖'
}
$items = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
if ($items.Count -gt 128) { throw '插件包最多包含 128 个条目' }
$total = 0L
foreach ($item in $items) {
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '插件包不允许链接文件' }
    if (-not $item.PSIsContainer) {
        if ($item.Length -gt 2MB) { throw "单个文件超过 2 MB: $($item.Name)" }
        $total += $item.Length
    }
}
if ($total -gt 20MB) { throw '插件包总资源超过 20 MB' }
$parent = [IO.Path]::GetDirectoryName($output)
[IO.Directory]::CreateDirectory($parent) | Out-Null
$pending = Join-Path $parent ([IO.Path]::GetRandomFileName() + '.zip')
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($source, $pending)
    if ((Get-Item -LiteralPath $pending).Length -gt 10MB) { throw '压缩包超过 10 MB' }
    Move-Item -LiteralPath $pending -Destination $output -Force:$Force
    Write-Output "插件包已生成: $output"
} finally {
    if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending }
}
