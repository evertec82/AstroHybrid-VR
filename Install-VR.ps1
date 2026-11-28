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
function Test-BytesEqual([byte[]]$a, [byte[]]$b) {
    if(!$a -or !$b -or $a.Length -ne $b.Length){return $false}
    for($i=0;$i -lt $a.Length;$i++){ if($a[$i] -ne $b[$i]){return $false} }
    return $true
}
function Read-ExactBytes([IO.Stream]$stream, [long]$offset, [int]$length) {
    if($offset -lt 0 -or ($offset+$length) -gt $stream.Length){return $null}
    $buf=New-Object byte[] $length
    $stream.Position=$offset
    $read=0
    while($read -lt $length){
        $n=$stream.Read($buf,$read,$length-$read)
        if($n -le 0){return $null}
        $read+=$n
    }
    return ,$buf
}
function Test-UpstreamHavokGuard([IO.Stream]$stream) {
    # AstroHybrid 1.2.4+ redirects siteOff (8902983) to caveA -> caveB before Setup finishes.
    $siteOff = 8902983L; $skipOff = 8902993L; $contactOff = 8903307L
    $site = Read-ExactBytes $stream $siteOff 10
    if(!$site -or $site[0] -ne 0xE9 -or !(Test-BytesEqual $site[5..9] ([byte[]]@(0x0F,0x1F,0x44,0x00,0x00)))){return $false}
    $caveA = $siteOff + 5 + [BitConverter]::ToInt32($site, 1)
    $a = Read-ExactBytes $stream $caveA 15
    if(!$a -or !(Test-BytesEqual $a[0..5] ([byte[]]@(0xC5,0xF8,0x2E,0xF7,0x0F,0x83))) -or $a[10] -ne 0xE9){return $false}
    if(($caveA + 10 + [BitConverter]::ToInt32($a, 6)) -ne $skipOff){return $false}
    $caveB = $caveA + 15 + [BitConverter]::ToInt32($a, 11)
    $b = Read-ExactBytes $stream $caveB 14
    if(!$b -or !(Test-BytesEqual $b[0..4] ([byte[]]@(0x4D,0x85,0xFF,0x0F,0x84))) -or $b[9] -ne 0xE9){return $false}
    if(($caveB + 9 + [BitConverter]::ToInt32($b, 5)) -ne $skipOff){return $false}
    if(($caveB + 14 + [BitConverter]::ToInt32($b, 10)) -ne $contactOff){return $false}
    return $true
}
foreach($process in [Diagnostics.Process]::GetProcesses()) {
    if($process.ProcessName -notlike 'AstroBot*'){continue}
    try { $same=$process.MainModule.FileName.StartsWith("$run\",[StringComparison]::OrdinalIgnoreCase) } catch { $same=$true }
    if($same){throw 'Close Astro Bot before installing the VR mod.'}
}
$base=Join-Path $run ($manifest.game.base_name+'.exe')
if(!(Test-Path -LiteralPath $base)) {
    throw 'First complete setup using AstroHybrid and your own decrypted PPSA21567 v01.019.000 dump. Extract this mod ZIP into that AstroHybrid folder, then run Install VR.bat.'
}
$details='Setup metadata unavailable.'
$info=$null
$infoPath=Join-Path $run 'astrohybrid-game.json'
if(Test-Path -LiteralPath $infoPath) {
    try {
        $info=Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
        $details="TitleId=$($info.TitleId) Version=$($info.Version) IntelConversion=$($info.IntelConversion)"
    } catch {}
}
$sourceHash=Hash-File $base
$sourceLength=(Get-Item -LiteralPath $base).Length
$conversion=$null
$knownConversion=$false
if($sourceHash -eq $manifest.game.source_sha256) {
    $conversion=$manifest.game
    $knownConversion=$true
} else {
    $match=@($manifest.game.conversions | Where-Object { $_.source_sha256 -eq $sourceHash })
    if($match.Count -eq 1) {
        $conversion=$match[0]
        $knownConversion=$true
    }
}
if(!$knownConversion -and $info) {
    if([string]$info.TitleId -ne [string]$manifest.game.title_id -or [string]$info.Version -ne [string]$manifest.game.version) {
        throw "Unsupported AstroHybrid conversion ($details). Expected TitleId=$($manifest.game.title_id) Version=$($manifest.game.version). Source SHA-256=$sourceHash. Installation stopped before patching."
    }
}
$sidecars=@(Get-ChildItem -LiteralPath $run -File | Where-Object { $_.Name.StartsWith($manifest.game.base_name+'.',[StringComparison]::Ordinal) -and $_.Name.EndsWith('.json') })
if($sidecars.Count -ne 6){throw 'The six loader sidecar files are missing. Run AstroHybrid setup again before installing VR.'}
foreach($file in $manifest.payload) {
    $path=Join-Path $PSScriptRoot $file.path
    if(!(Test-Path -LiteralPath $path) -or (Hash-File $path) -ne $file.sha256){throw "VR package verification failed: $($file.path)"}
}
$havokOffsets=@(8902987L, 8893441L)
$skipUpstreamHavok=$false
$stream=[IO.File]::OpenRead($base)
try {
    foreach($patch in $manifest.game.patches) {
        $expected=Hex-Bytes $patch.before
        $actual=Read-ExactBytes $stream ([long]$patch.offset) $expected.Length
        if($actual -and (Test-BytesEqual $actual $expected)){continue}
        if(!$knownConversion -and ([long]$patch.offset -in $havokOffsets) -and (Test-UpstreamHavokGuard $stream)) {
            $skipUpstreamHavok=$true
            continue
        }
        throw "Executable signature mismatch at $($patch.offset) ($details; Source SHA-256=$sourceHash). Run Check Conversion.bat and include AstroHybrid-conversion-report.json when reporting the issue. No patch was applied."
    }
} finally {$stream.Dispose()}
& (Join-Path $PSScriptRoot 'Install-HudLayout.ps1') -RunDirectory $run -ValidateOnly
if($ValidateOnly){'Package, executable signatures, HUD layouts and loader files verified.';exit 0}

foreach ($targetName in @($manifest.game.target_name, $manifest.game.dlss_target_name)) {
    $patches=$manifest.game.patches
    $targetHash=if($knownConversion){$conversion.target_sha256}else{$null}
    if ($targetName -eq $manifest.game.dlss_target_name) {
        $patches=@($patches | Where-Object { $_.offset -in $manifest.game.dlss_patch_offsets })
        $targetHash=if($knownConversion){$conversion.dlss_sha256}else{$null}
    }
    if($skipUpstreamHavok) {
        $patches=@($patches | Where-Object { [long]$_.offset -notin $havokOffsets })
    }
    $candidate=Join-Path $run ($targetName+'.exe')
    $temporary=$candidate+'.vr-install.tmp'
    try {
        [IO.File]::Copy($base,$temporary,$true)
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
        try {
            foreach($patch in $patches) {
                $replacement=Hex-Bytes $patch.after
                $stream.Position=[long]$patch.offset
                $stream.Write($replacement,0,$replacement.Length)
            }
            $stream.Flush()
            if(!$knownConversion) {
                if($stream.Length -ne $sourceLength){throw 'Patched executable size verification failed.'}
                foreach($patch in $patches) {
                    $expectedAfter=Hex-Bytes $patch.after
                    $written=Read-ExactBytes $stream ([long]$patch.offset) $expectedAfter.Length
                    if(!$written -or !(Test-BytesEqual $written $expectedAfter)) {
                        throw "Patched executable verification failed at $($patch.offset)."
                    }
                }
                if($skipUpstreamHavok -and !(Test-UpstreamHavokGuard $stream)) {
                    throw 'Patched executable Havok guard verification failed.'
                }
            }
        } finally {$stream.Dispose()}
        if($knownConversion -and (Hash-File $temporary) -ne $targetHash){throw 'Patched executable verification failed.'}
        Move-Item -LiteralPath $temporary -Destination $candidate -Force
    } finally {if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    foreach($sidecar in $sidecars) {
        $name=$targetName+$sidecar.Name.Substring($manifest.game.base_name.Length)
        Copy-Item -LiteralPath $sidecar.FullName -Destination (Join-Path $run $name) -Force
    }
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
[IO.File]::WriteAllText((Join-Path $run 'AstroHybridVR.version'),[string]$manifest.version)

$fg=Join-Path $root 'Build\FrameGeneration'
$xrDir=Join-Path $fg 'manifests\openxr'; $vkDir=Join-Path $fg 'manifests\vulkan'
New-Item -ItemType Directory -Path $xrDir,$vkDir -Force | Out-Null
@{file_format_version='1.0.0';api_layer=@{name='XR_APILAYER_OFXRBridge';library_path=(Join-Path $fg 'ofxr\XR_APILAYER_XRFrameBridge_diagnostic.dll');api_version='1.0';implementation_version='983';description='AstroHybrid VR local frame generation'}} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $xrDir 'openxr-ofxr.json') -Encoding Ascii
@{file_format_version='1.2.0';layer=@{name='VK_LAYER_OFXRBridge_queue_serialize';type='GLOBAL';library_path=(Join-Path $fg 'ofxr\OFXR_vulkan_queue_layer.dll');api_version='1.3.296';implementation_version='983';description='AstroHybrid VR queue synchronization';functions=@{vkNegotiateLoaderLayerInterfaceVersion='OFXR_vkNegotiateLoaderLayerInterfaceVersion';vkGetInstanceProcAddr='OFXR_vkGetInstanceProcAddr';vkGetDeviceProcAddr='OFXR_vkGetDeviceProcAddr'}}} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $vkDir 'vulkan-ofxr.json') -Encoding Ascii
& (Join-Path $PSScriptRoot 'Install-HudLayout.ps1') -RunDirectory $run
Write-Output 'VR installation complete. Open Play AstroHybrid VR - Launcher.bat.'
Write-Output "Original renderer backup: $backup"
