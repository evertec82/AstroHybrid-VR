param([switch]$ValidateOnly, [switch]$ApplyOnly, [switch]$PreviewOnly, [string]$SettingsFile)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (!$SettingsFile) { $SettingsFile = Join-Path $root 'vr-launcher-settings.json' }
$widths = @(2048, 2560, 3200, 3520, 4512, 5184, 6000)
$dlssModes = @('Performance','Balanced','Quality','DLAA')

function Read-Settings {
    $settings = [ordered]@{ ResolutionWidth=3520; DlssSuperResolution=$false; DlssMode='Quality'; FrameGeneration=$true; Multiplier=2; FlowQuality='Medium'; FlowResolution=25; Overlay=$false; VerboseLogging=$false; SkipIntro=$false }
    if (Test-Path -LiteralPath $SettingsFile) {
        $saved = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
        foreach ($key in @($settings.Keys)) {
            if ($saved.PSObject.Properties.Name -contains $key) { $settings[$key] = $saved.$key }
        }
    }
    if ($settings.ResolutionWidth -in @(6656, 7168, 8192)) { $settings.ResolutionWidth = 6000 }
    if ($settings.ResolutionWidth -notin $widths) { throw 'Unsupported resolution preset.' }
    if ($settings.DlssMode -cnotin $dlssModes) { throw 'Unsupported DLSS mode.' }
    if ($settings.Multiplier -notin @(2,3,4)) { throw 'Unsupported frame-generation multiplier.' }
    if ($settings.FlowQuality -notin @('Fast','Medium','Quality')) { throw 'Unsupported flow quality.' }
    if ($settings.FlowResolution -notin @(25,50,75,100)) { throw 'Unsupported flow resolution.' }
    foreach ($key in @('DlssSuperResolution','FrameGeneration','Overlay','VerboseLogging','SkipIntro')) {
        if ($settings[$key] -isnot [bool]) { throw "Invalid boolean setting: $key" }
    }
    if ($settings.ResolutionWidth -eq 6000 -and (!$settings.DlssSuperResolution -or $settings.DlssMode -eq 'DLAA')) {
        $settings.DlssSuperResolution=$true
        $settings.DlssMode='Performance'
    }
    return $settings
}
function Save-Settings($settings) {
    $temporary = "$SettingsFile.tmp"
    $settings | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $SettingsFile -Force
}
function Set-IniValue($lines, [string]$section, [string]$key, [string]$value) {
    $start = -1; $end = $lines.Count
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq "[$section]") { $start=$i; break }
    }
    if ($start -ge 0) {
        for ($i=$start+1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim().StartsWith('[')) { $end=$i; break } }
        for ($i=$start+1; $i -lt $end; $i++) {
            if ($lines[$i] -match ('^\s*' + [regex]::Escape($key) + '\s*=')) {
                if ($lines[$i] -ceq "$key=$value") { return $false }
                $lines[$i]="$key=$value"
                return $true
            }
        }
        $lines.Insert($end,"$key=$value")
    } else { $lines.Add("[$section]"); $lines.Add("$key=$value") }
    return $true
}
function Update-IniFile([string]$path, [System.Collections.IDictionary]$sections) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    if ([IO.File]::Exists($path)) { $lines.AddRange([string[]][IO.File]::ReadAllLines($path)) }
    $changed = $false
    foreach ($section in $sections.Keys) {
        foreach ($key in $sections[$section].Keys) {
            if (Set-IniValue $lines $section $key $sections[$section][$key]) { $changed = $true }
        }
    }
    if (!$changed) { return }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
    [IO.File]::WriteAllLines($path,$lines)
}
function File-Hash([string]$path) {
    $stream=[IO.File]::OpenRead($path); $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Game-Executable($settings) {
    if ($settings.DlssSuperResolution -and $settings.DlssMode -ne 'DLAA') { return 'AstroBot-NonRT-SoftAssert-DLSS-PhysicsGuard.exe' }
    return 'AstroBot-NonRT-SoftAssert-Gameplay4K-PhysicsGuard.exe'
}
function Apply-Settings($settings) {
    $run = Join-Path $root 'Build\RunHybrid'
    $game = Join-Path $run (Game-Executable $settings)
    if (!(Test-Path -LiteralPath $game)) { throw "Missing game executable: $game" }
    $running = [Diagnostics.Process]::GetProcesses() | Where-Object { $_.ProcessName -like 'AstroBot*' } | Where-Object { try { $_.MainModule.FileName.StartsWith("$run\",[StringComparison]::OrdinalIgnoreCase) } catch { $true } }
    if ($running) { throw 'Close Astro Bot before starting another session or applying these settings.' }
    $staged = Join-Path $root 'Build\HeadsetProjectionPreview\kyty_gpu.dll'
    $detailedDraws = $settings.VerboseLogging -or
                     ($env:KYTY_STEREO_COMMIT_TIMING -eq '1') -or
                     ($env:KYTY_CP_COMMIT_STATS -and $env:KYTY_CP_COMMIT_STATS -ne '0') -or
                     ($env:KYTY_BUFFER_LOOKUP_STATS -and $env:KYTY_BUFFER_LOOKUP_STATS -ne '0')
    if ($settings.DlssSuperResolution) {
        $staged = Join-Path (Split-Path $staged) 'kyty_gpu.dlss.dll'
        if (!(Test-Path -LiteralPath $staged -PathType Leaf)) { throw 'The stereo DLSS renderer is missing.' }
    } elseif ($detailedDraws) {
        $diagnosticRenderer = Join-Path (Split-Path $staged) 'kyty_gpu.diagnostics.dll'
        if (Test-Path -LiteralPath $diagnosticRenderer -PathType Leaf) { $staged = $diagnosticRenderer }
    }
    $installed = Join-Path $run 'kyty_gpu.dll'
    $hash = File-Hash $staged
    if ((File-Hash $installed) -ne $hash) {
        [IO.File]::Copy($staged,$installed,$true)
        if ((File-Hash $installed) -ne $hash) { throw 'The renderer copy could not be verified.' }
    }
    [IO.File]::WriteAllText((Join-Path $run 'AstroHybridVR.ready'),$hash)
    $folder = Join-Path $root 'Build\FrameGeneration'
    if ($settings.FrameGeneration -and !(Test-Path -LiteralPath (Join-Path $folder 'ofxr\XR_APILAYER_XRFrameBridge_diagnostic.dll'))) { throw 'The frame-generation package is missing.' }
    $preset = @{Fast=2;Medium=1;Quality=0}[$settings.FlowQuality]
    $scale = @{25=3;50=2;75=1;100=0}[[int]$settings.FlowResolution]
    foreach ($relative in @('Profiles\ofxr-bridge.ini',("Profiles\Profiles\" + (Game-Executable $settings) + '.ini'))) {
        $path=Join-Path $folder $relative
        Update-IniFile $path ([ordered]@{
            ofxr = [ordered]@{ enabled=1; frame_generation=0; backend=2; motion_vectors=0; ofr_enabled=0; preset=$preset; scale=$scale; frame_multiplier=$settings.Multiplier; overlay_enabled=[int]$settings.Overlay; diagnostics=[int]$settings.VerboseLogging }
            'route.ofxr_new' = [ordered]@{ motion_vectors=0; preset=$preset; scale=$scale; frame_multiplier=$settings.Multiplier }
        })
    }
    $ini=Join-Path $folder 'ofxr\ofxr_bridge.ini'
    Update-IniFile $ini ([ordered]@{
        overlay = @{ position=$(if($settings.Overlay){'elliott_bottom'}else{'off'}) }
        diagnostics = @{ logging_enabled=[int]$settings.VerboseLogging }
    })
    Save-Settings $settings
}
function Use-LargeEyeTargets($width,$sr,$mode,$frameGeneration) {
    if ($width -eq 6000 -or ($width -eq 3200 -and $sr -and $mode -ne 'DLAA')) { return $true }
    if ($frameGeneration) { return $false }
    return $width -eq 3520 -or ($width -eq 4512 -and (!$sr -or $mode -ne 'DLAA')) -or ($width -eq 5184 -and $sr -and $mode -ne 'DLAA')
}
function Start-Game($settings) {
    Apply-Settings $settings
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$env:ComSpec
    $start.Arguments='/d /c "Play AstroHybrid VR.bat"'
    $start.WorkingDirectory=$root; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $environment=$start.EnvironmentVariables
    # A full allocation census walks both driver and emulator data on the rendering thread.
    if (!$environment.ContainsKey('KYTY_VRAM_STATS')) {
        $environment['KYTY_VRAM_STATS'] = [string][int]$settings.VerboseLogging
    }
    $environment['ASTROHYBRID_EXE']=(Game-Executable $settings)
    $environment['ASTROHYBRID_DLSS']=[string][int]$settings.DlssSuperResolution
    if ($settings.DlssSuperResolution) {
        $environment['ASTROHYBRID_CUDA_HOLE']='1'
        $environment['ASTROHYBRID_DLSS_QUALITY']=$settings.DlssMode.ToLowerInvariant()
    }
    $environment['ASTROHYBRID_VR_HEADSET_PROJECTION']='1'
    $environment['KYTY_VR_EYE_WIDTH']="$($settings.ResolutionWidth)"
    $environment['KYTY_VR_OUTPUT_PIXELS']='6.5'
    $environment['ASTROHYBRID_SKIP_INTRO']="$([int]$settings.SkipIntro)"
    $large=Use-LargeEyeTargets $settings.ResolutionWidth $settings.DlssSuperResolution $settings.DlssMode $settings.FrameGeneration
    $environment['ASTROHYBRID_VR_LARGE_TARGETS']=[string][int]$large
    if ($large) {
        $environment['KYTY_GUEST_BACKING_LAZY_COMMIT']='1'
        $environment['KYTY_GUEST_BACKING_LAZY_ZERO']='1'
        $environment['KYTY_NATIVE_IMAGE_POOL_MB']='64'
        $environment['KYTY_TILER_SCRATCH_POOL_MB']='32'
        $environment['KYTY_VRAM_IDLE_FRAMES']='90'
        if ($settings.ResolutionWidth -ge 4512) {
            $environment['KYTY_VRAM_IDLE_FRAMES']='30'
            $environment['KYTY_VRAM_PRESSURE_FRAMES']='8'
            $environment['KYTY_VRAM_GC_BUDGET']='1'
            $environment['KYTY_VRAM_BUDGET_MB']='21000'
            $environment['KYTY_RAM_SMALL_UPLOAD_RING']='1'
            $environment['KYTY_STREAM_RING_HOST']='1'
            $environment['KYTY_TILER_SCRATCH_POOL_MB']='16'
            $environment['KYTY_NATIVE_IMAGE_POOL_MB']='32'
        }
    }
    # Isolate the chosen mode from older globally armed OFXR copies.
    $environment['XRFG_DISABLE_OFXR_BRIDGE']='1'
    $environment['OFXR_DISABLE_VULKAN_QUEUE_LAYER']='1'
    $environment['KYTY_VR_FRAME_GENERATION']='off'
    if ($settings.FrameGeneration) {
        $folder=Join-Path $root 'Build\FrameGeneration'
        $environment['XR_API_LAYER_PATH']=Join-Path $folder 'manifests\openxr'
        $environment['VK_ADD_LAYER_PATH']=Join-Path $folder 'manifests\vulkan'
        $environment['VK_INSTANCE_LAYERS']='VK_LAYER_OFXRBridge_queue_serialize'
        $environment['OFXR_BRIDGE_PROFILE_DIR']=Join-Path $folder 'Profiles'
        $environment['KYTY_VR_FRAME_GENERATION']='ofxr'
        # Cache planning headroom for OFXR/compositor allocations on this 32 GB GPU.
        # This is an eviction target, not a hard allocation or render-resolution limit.
        if (!$environment['KYTY_VRAM_BUDGET_MB']) { $environment['KYTY_VRAM_BUDGET_MB']='24576' }
    } else {
        $environment['XR_ENABLE_API_LAYERS']=''
        $environment['VK_INSTANCE_LAYERS']=''
    }
    [Diagnostics.Process]::Start($start) | Out-Null
}

$settings=Read-Settings
if ($ValidateOnly) { $settings | ConvertTo-Json; exit 0 }
if ($ApplyOnly) { Apply-Settings $settings; 'Settings applied; game was not launched.'; exit 0 }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object Windows.Forms.Form
$form.Text='AstroHybrid VR Launcher'; $form.ClientSize=New-Object Drawing.Size(560,560)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$header=New-Object Windows.Forms.Label
$header.Text='Astro Bot VR'; $header.Font=New-Object Drawing.Font('Segoe UI',18,[Drawing.FontStyle]::Bold)
$header.SetBounds(24,16,500,38); $form.Controls.Add($header)
$intro=New-Object Windows.Forms.Label
$intro.Text='Both eyes render in the same game frame. Settings are saved for next time.'
$intro.SetBounds(25,61,510,45); $form.Controls.Add($intro)
function Add-Choice([string]$label,[int]$y,[object[]]$items,[object]$selected) {
    $caption=New-Object Windows.Forms.Label; $caption.Text=$label; $caption.SetBounds(25,$y+4,225,26); $form.Controls.Add($caption)
    $choice=New-Object Windows.Forms.ComboBox; $choice.DropDownStyle='DropDownList'
    $choice.SetBounds(260,$y,270,28); foreach($item in $items){[void]$choice.Items.Add([string]$item)}
    $choice.SelectedItem=[string]$selected; $form.Controls.Add($choice); return $choice
}
$resolution=Add-Choice 'Per-eye output width' 112 @($widths | ForEach-Object {"$_ pixels"}) "$($settings.ResolutionWidth) pixels"
$hint=New-Object Windows.Forms.Label
$showResolutionHint={
    $width=[int]($resolution.SelectedItem -replace ' pixels','')
    $dlss.Enabled=($width -ne 6000)
    if ($width -eq 6000) {
        if (!$dlss.Checked -or $dlssMode.SelectedItem -eq 'DLAA') {
            $dlssMode.SelectedItem='Performance'
            $dlss.Checked=$true
        }
        $hint.Text='DLSS reconstructs to the full headset target. Performance uses the least memory.'
    } elseif ($width -le 3200 -or (Use-LargeEyeTargets $width $dlss.Checked $dlssMode.SelectedItem $generation.Checked)) {
        $hint.Text='Scene output follows the per-eye size within the verified pixel budget.'
    } else {
        $hint.Text=switch ($width) {
            3520 { 'For full per-eye resolution, turn off frame generation.' }
            4512 { 'For full resolution, turn off frame generation and use native or DLSS Super Resolution.' }
            5184 { 'For full resolution, turn off frame generation and select DLSS Quality, Balanced or Performance.' }
            default { 'Headset output is scaled from the game image at this preset.' }
        }
    }
}
$resolution.Add_SelectedIndexChanged($showResolutionHint)
$hint.SetBounds(25,148,510,40); $hint.ForeColor=[Drawing.Color]::DimGray; $form.Controls.Add($hint)
$generation=New-Object Windows.Forms.CheckBox; $generation.Text='Enable NVIDIA optical-flow frame generation'
$generation.SetBounds(25,190,510,28); $generation.Checked=$settings.FrameGeneration; $form.Controls.Add($generation)
$multiplier=Add-Choice 'Generated output multiplier' 228 @('2x','3x','4x') "$($settings.Multiplier)x"
$quality=Add-Choice 'Optical-flow quality' 267 @('Fast','Medium','Quality') $settings.FlowQuality
$flow=Add-Choice 'Flow estimation resolution' 306 @('25%','50%','75%','100%') "$($settings.FlowResolution)%"
$overlay=New-Object Windows.Forms.CheckBox; $overlay.Text='Show performance overlay'; $overlay.Checked=$settings.Overlay
$overlay.SetBounds(25,351,300,27); $form.Controls.Add($overlay)
$logging=New-Object Windows.Forms.CheckBox; $logging.Text='Detailed diagnostics (may reduce performance)'; $logging.Checked=$settings.VerboseLogging
$logging.SetBounds(25,380,500,27); $form.Controls.Add($logging)
$skip=New-Object Windows.Forms.CheckBox; $skip.Text='Skip intro'; $skip.Checked=$settings.SkipIntro
$skip.SetBounds(25,409,300,27); $form.Controls.Add($skip)
$updateChoices={ $multiplier.Enabled=$generation.Checked; $quality.Enabled=$generation.Checked; $flow.Enabled=$generation.Checked; $overlay.Enabled=$generation.Checked }
$generation.Add_CheckedChanged($updateChoices); & $updateChoices
$dlss=New-Object Windows.Forms.CheckBox; $dlss.Text='DLSS Super Resolution (RTX, experimental)'; $dlss.Checked=$settings.DlssSuperResolution
$dlss.SetBounds(25,437,490,26); $form.Controls.Add($dlss)
$dlssMode=Add-Choice 'DLSS mode' 469 $dlssModes $settings.DlssMode
$dlssMode.Enabled=$dlss.Checked
$dlss.Add_CheckedChanged({ $dlssMode.Enabled=$dlss.Checked })
$dlss.Add_CheckedChanged($showResolutionHint)
$dlssMode.Add_SelectedIndexChanged($showResolutionHint)
$generation.Add_CheckedChanged($showResolutionHint)
& $showResolutionHint
function Get-Selections {
    return [ordered]@{DlssSuperResolution=$dlss.Checked; DlssMode=[string]$dlssMode.SelectedItem; ResolutionWidth=[int]($resolution.SelectedItem -replace ' pixels',''); FrameGeneration=$generation.Checked; Multiplier=[int]($multiplier.SelectedItem -replace 'x',''); FlowQuality=[string]$quality.SelectedItem; FlowResolution=[int]($flow.SelectedItem -replace '%',''); Overlay=$overlay.Checked; VerboseLogging=$logging.Checked; SkipIntro=$skip.Checked}
}
$save=New-Object Windows.Forms.Button; $save.Text='Save'; $save.SetBounds(193,510,100,33); $form.Controls.Add($save)
$save.Add_Click({try {Save-Settings (Get-Selections); $save.Text='Saved'} catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings') | Out-Null}})
$cancel=New-Object Windows.Forms.Button; $cancel.Text='Close'; $cancel.SetBounds(306,510,100,33); $form.Controls.Add($cancel); $cancel.Add_Click({$form.Close()})
$play=New-Object Windows.Forms.Button; $play.Text='Start VR'; $play.SetBounds(419,510,110,33); $form.Controls.Add($play)
$play.Add_Click({try {Start-Game (Get-Selections); $form.Close()} catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Unable to start VR') | Out-Null}})
$form.AcceptButton=$play; $form.CancelButton=$cancel
if ($PreviewOnly) { $play.Enabled=$false; $form.AcceptButton=$null }
[void]$form.ShowDialog()
$form.Dispose()
