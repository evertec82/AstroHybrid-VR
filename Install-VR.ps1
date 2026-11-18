param([string]$InstallDirectory = $PSScriptRoot, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($InstallDirectory)
$run = Join-Path $root 'Build\RunHybrid'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vr-package.json') -Raw | ConvertFrom-Json
function Hash-File([string]$path) {
    $stream=[IO.File]::OpenRead($path); $hash=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $hash.Dispose(); $stream.Dispose() }
}
function Hex-Bytes([string]$hex) {
    $bytes=New-Object byte[] ($hex.Length/2)
    for($i=0;$i -lt $bytes.Length;$i++){ $bytes[$i]=[Convert]::ToByte($hex.Substring($i*2,2),16) }
    return ,$bytes
}
foreach($process in [Diagnostics.Process]::GetProcesses()) {
    if($process.ProcessName -notlike 'AstroBot*'){continue}
    try { $same=$process.MainModule.FileName.StartsWith("$run\",[StringComparison]::OrdinalIgnoreCase) } catch { $same=$true }
    if($same){throw 'Close Astro Bot before installing the VR mod.'}
}
$base=Join-Path $run ($manifest.game.base_name+'.exe')
if(!(Test-Path -LiteralPath $base)) {
    throw 'First complete setup using AstroHybrid 1.2.1 and your own decrypted PPSA21567 v01.019.000 dump. Extract this mod ZIP into that AstroHybrid folder, then run Install VR.bat.'
}
if((Hash-File $base) -ne $manifest.game.source_sha256) {
    throw 'This converted executable is not the supported build. VR installation stopped without patching it. Supported: PPSA21567 v01.019.000, AstroHybrid NonRT-SoftAssert variant. See README.md.'
}
$sidecars=@(Get-ChildItem -LiteralPath $run -File | Where-Object { $_.Name.StartsWith($manifest.game.base_name+'.',[StringComparison]::Ordinal) -and $_.Name.EndsWith('.json') })
if($sidecars.Count -ne 6){throw 'The six loader sidecar files are missing. Run AstroHybrid setup again before installing VR.'}
foreach($file in $manifest.payload) {
    $path=Join-Path $PSScriptRoot $file.path
    if(!(Test-Path -LiteralPath $path) -or (Hash-File $path) -ne $file.sha256){throw "VR package verification failed: $($file.path)"}
}
$stream=[IO.File]::OpenRead($base)
try {
    foreach($patch in $manifest.game.patches) {
        $expected=Hex-Bytes $patch.before
        $actual=New-Object byte[] $expected.Length
        $stream.Position=[long]$patch.offset
        if($stream.Read($actual,0,$actual.Length) -ne $actual.Length -or [BitConverter]::ToString($actual) -ne [BitConverter]::ToString($expected)) {
            throw "Executable signature mismatch at $($patch.offset). No patch was applied."
        }
    }
} finally {$stream.Dispose()}
if($ValidateOnly){'Package, executable signatures and loader files verified. No changes made.';exit 0}

$candidate=Join-Path $run ($manifest.game.target_name+'.exe')
$temporary=$candidate+'.vr-install.tmp'
try {
    [IO.File]::Copy($base,$temporary,$true)
    $stream=[IO.File]::Open($temporary,[IO.FileMode]::Open,[IO.FileAccess]::Write)
    try {
        foreach($patch in $manifest.game.patches) {
            $replacement=Hex-Bytes $patch.after
            $stream.Position=[long]$patch.offset
            $stream.Write($replacement,0,$replacement.Length)
        }
    } finally {$stream.Dispose()}
    if((Hash-File $temporary) -ne $manifest.game.target_sha256){throw 'Patched executable verification failed.'}
    Move-Item -LiteralPath $temporary -Destination $candidate -Force
} finally {if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
foreach($sidecar in $sidecars) {
    $name=$manifest.game.target_name+$sidecar.Name.Substring($manifest.game.base_name.Length)
    Copy-Item -LiteralPath $sidecar.FullName -Destination (Join-Path $run $name) -Force
}
$backup=Join-Path $root ('VR-backup-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
foreach($relative in @('kyty_gpu.dll','libs\libSceVideoOut.prx')) {
    $existing=Join-Path $run $relative
    if(Test-Path -LiteralPath $existing){ Copy-Item -LiteralPath $existing -Destination (Join-Path $backup ([IO.Path]::GetFileName($relative))) -Force }
}
Copy-Item -LiteralPath (Join-Path $root 'Build\HeadsetProjectionPreview\kyty_gpu.dll') -Destination (Join-Path $run 'kyty_gpu.dll') -Force
Copy-Item -LiteralPath (Join-Path $root 'VR-support\libSceVideoOut.prx') -Destination (Join-Path $run 'libs\libSceVideoOut.prx') -Force
[IO.File]::WriteAllText((Join-Path $run 'AstroHybridVR.ready'),(Hash-File (Join-Path $run 'kyty_gpu.dll')).ToUpperInvariant())

$fg=Join-Path $root 'Build\FrameGeneration'
$xrDir=Join-Path $fg 'manifests\openxr'; $vkDir=Join-Path $fg 'manifests\vulkan'
New-Item -ItemType Directory -Path $xrDir,$vkDir -Force | Out-Null
@{file_format_version='1.0.0';api_layer=@{name='XR_APILAYER_OFXRBridge';library_path=(Join-Path $fg 'ofxr\XR_APILAYER_XRFrameBridge_diagnostic.dll');api_version='1.0';implementation_version='983';description='AstroHybrid VR local frame generation'}} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $xrDir 'openxr-ofxr.json') -Encoding Ascii
@{file_format_version='1.2.0';layer=@{name='VK_LAYER_OFXRBridge_queue_serialize';type='GLOBAL';library_path=(Join-Path $fg 'ofxr\OFXR_vulkan_queue_layer.dll');api_version='1.3.296';implementation_version='983';description='AstroHybrid VR queue synchronization';functions=@{vkNegotiateLoaderLayerInterfaceVersion='OFXR_vkNegotiateLoaderLayerInterfaceVersion';vkGetInstanceProcAddr='OFXR_vkGetInstanceProcAddr';vkGetDeviceProcAddr='OFXR_vkGetDeviceProcAddr'}}} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $vkDir 'vulkan-ofxr.json') -Encoding Ascii
Write-Output 'VR installation complete. Open Play AstroHybrid VR - Launcher.bat.'
Write-Output "Original renderer backup: $backup"
