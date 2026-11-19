param([string]$Root=$PSScriptRoot, [string]$Report)
$ErrorActionPreference='Stop'
$run=Join-Path $Root 'Build\RunHybrid'
$exe=Join-Path $run 'AstroBot-NonRT-SoftAssert.exe'
if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Extract both diagnostic files beside Install VR.bat and try again.' }
if (!$Report) { $Report=Join-Path $Root 'AstroHybrid-conversion-report.json' }
$result=[ordered]@{ executable='AstroBot-NonRT-SoftAssert.exe'; bytes=(Get-Item -LiteralPath $exe).Length; sha256=(Get-FileHash -LiteralPath $exe).Hash; blockBytes=1048576 }
foreach ($name in @('AstroBot.exe','astrohybrid-game.json')) {
    $path=Join-Path $run $name
    if (Test-Path -LiteralPath $path) {
        if ($name -eq 'AstroBot.exe') { $result.baseSha256=(Get-FileHash -LiteralPath $path).Hash }
        else { $result.setup=(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Select-Object TitleId,Version,IntelConversion,FasterLighting,GameStepAddress) }
    }
}
foreach ($item in @(@('relinkerSha256','tools\relinker.exe'),@('ebootSha256','Build\RunHybrid\app0\eboot.bin'))) {
    $path=Join-Path $Root $item[1]
    if (Test-Path -LiteralPath $path -PathType Leaf) { $result[$item[0]]=(Get-FileHash -LiteralPath $path).Hash }
}
$stream=[IO.File]::OpenRead($exe)
$hash=[Security.Cryptography.SHA256]::Create()
try {
    $buffer=New-Object byte[] $result.blockBytes
    $result.blockHashes=@(while($stream.Position -lt $stream.Length) {
        $count=[int][Math]::Min([long]$buffer.Length, $stream.Length-$stream.Position)
        $read=0
        while ($read -lt $count) {
            $n=$stream.Read($buffer,$read,$count-$read)
            if (!$n) {throw 'Incomplete read of the converted executable.'}
            $read+=$n
        }
        [BitConverter]::ToString($hash.ComputeHash($buffer,0,$count)).Replace('-','')
    })
} finally { $hash.Dispose(); $stream.Dispose() }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host "Created $Report"
