param([Parameter(Mandatory=$true)][string]$RunDirectory, [switch]$ValidateOnly, [switch]$Restore)
$ErrorActionPreference='Stop'
$data=Join-Path $RunDirectory 'app0\data'
$work=Join-Path (Split-Path $RunDirectory -Parent) 'VR-HUD'
$original=Join-Path $work 'original-data'
$active=Get-Item -LiteralPath $data
if($active.LinkType -notin 'Junction','SymbolicLink'){throw "Expected an AstroHybrid data link at $data"}
$saved=Get-Item -LiteralPath $original -ErrorAction SilentlyContinue
if($saved -and ([IO.Path]::GetDirectoryName([string]@($active.Target)[0]) -ne $work)){throw 'The VR HUD backup belongs to a different active layout.'}
if($Restore){
    if(!$saved){return}
    $detached=Join-Path $work ('detached-'+[Guid]::NewGuid())
    [IO.Directory]::Move($data,$detached)
    try{[IO.Directory]::Move($original,$data)}catch{[IO.Directory]::Move($detached,$data);throw}
    [IO.Directory]::Delete($detached)
    return
}
$source=[string]@($active.Target)[0]
if($saved){$source=[string]@($saved.Target)[0]}
$encoding=[Text.Encoding]::GetEncoding(28591)
$layouts=@{}
function Replace-LayoutText($text,$before,$after){
    $index=$text.IndexOf($before,[StringComparison]::Ordinal)
    if($before.Length -ne $after.Length -or $index -lt 0 -or $text.LastIndexOf($before,[StringComparison]::Ordinal) -ne $index){
        throw "Unexpected HUD asset content near $before"
    }
    return $text.Remove($index,$before.Length).Insert($index,$after)
}
function Move-Anchor($text,$name,$before,$after){
    $start=$text.IndexOf("<Name>$name</Name>",[StringComparison]::Ordinal)
    if($start -lt 0){throw "Missing HUD anchor $name"}
    $end=$text.IndexOf('</LevelObject>',$start,[StringComparison]::Ordinal)
    $block=$text.Substring($start,$end-$start)
    if($block.Contains('<Parent>') -or !$block.Contains('<Scene type="Enum">1</Scene>')){throw "Unexpected HUD parent for $name"}
    $field='<Position type="Vector3">{0}</Position>'
    return $text.Substring(0,$start)+(Replace-LayoutText $block ($field -f $before) ($field -f $after))+$text.Substring($end)
}
foreach($file in 'prompt','holoboard','construction'){
    $key="prein\save_data\$file.xml"
    $text=$encoding.GetString([IO.File]::ReadAllBytes((Join-Path $source $key)))
    $layouts[$key]=Replace-LayoutText $text '<SafeFrameSize>+90.000 +90.000 +0.000</SafeFrameSize>' '<SafeFrameSize>330.000 210.000 +0.000</SafeFrameSize>'
}
$key='prein\levels\ui_coin_counter\level.lvx'
$text=$encoding.GetString([IO.File]::ReadAllBytes((Join-Path $source $key)))
$text=Move-Anchor $text '|ui_counter_coin' '11.6 9 0' '8.00 6 0'
$layouts[$key]=Move-Anchor $text '|ui_counter_coin_batch' '14.1974 7.8 0' '10.0974 5.5 0'
$key='prein\levels\ui_level_name_banner\level.lvx'
$text=$encoding.GetString([IO.File]::ReadAllBytes((Join-Path $source $key)))
$layouts[$key]=Move-Anchor $text '|ui_level_name_banner_ui' '0 5.4 -0.05' '0 3.7 -0.05'
if($saved){
    foreach($key in $layouts.Keys){
        if($encoding.GetString([IO.File]::ReadAllBytes((Join-Path $data $key))) -cne $layouts[$key]){throw "Active HUD layout differs at $key"}
    }
    return
}
if($ValidateOnly){return}
$layer=Join-Path $work ('layout-'+[Guid]::NewGuid())
$null=[IO.Directory]::CreateDirectory($layer)
function Build-LayoutFolder([string]$relative){
    $src=if($relative){Join-Path $source $relative}else{$source}
    foreach($entry in Get-ChildItem -LiteralPath $src -Force){
        $key=if($relative){Join-Path $relative $entry.Name}else{$entry.Name}
        $output=Join-Path $layer $key
        if($layouts.ContainsKey($key)){
            [IO.File]::WriteAllBytes($output,$encoding.GetBytes($layouts[$key]))
        }elseif($entry.PSIsContainer){
            if(@($layouts.Keys | Where-Object {$_.StartsWith($key+'\',[StringComparison]::OrdinalIgnoreCase)}).Count){
                $null=[IO.Directory]::CreateDirectory($output)
                Build-LayoutFolder $key
            }else{
                try{$null=New-Item -ItemType Junction -Path $output -Target $entry.FullName}
                catch{$null=New-Item -ItemType SymbolicLink -Path $output -Target $entry.FullName}
            }
        }else{
            try{$null=New-Item -ItemType HardLink -Path $output -Target $entry.FullName}
            catch{[IO.File]::Copy($entry.FullName,$output)}
        }
    }
}
Build-LayoutFolder ''
foreach($key in $layouts.Keys){
    if($encoding.GetString([IO.File]::ReadAllBytes((Join-Path $layer $key))) -cne $layouts[$key]){throw "Failed to stage $key"}
}
$link=$layer+'-link'
$null=New-Item -ItemType Junction -Path $link -Target $layer
[IO.Directory]::Move($data,$original)
try{[IO.Directory]::Move($link,$data)}catch{[IO.Directory]::Move($original,$data);throw}
