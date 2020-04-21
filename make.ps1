$version = (Get-Content version.txt)
$mod = 'pump_' + $version
$stagedir = '.build\' + $mod
$stagedirInfoJson = $stagedir + '\info.json'
$7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

Write-Output '#Clear the build dir'
Remove-Item -Path .build -Force -Recurse

Write-Output '#Copy content to staging directory'
New-Item -ItemType "directory" -Path $stagedir
Copy-Item mod\* -Destination $stagedir -Recurse

Write-Output '#Apply version'
(Get-Content $stagedirInfoJson).replace('<%version%>', $version) | Set-Content $stagedirInfoJson

Write-Output '#Bundle'
if (-not (Test-Path -Path $7zipPath -PathType Leaf)) {
    throw "7 zip file '$7zipPath' not found"
}
& $7zipPath a -tzip ('.build\' + $mod + '.zip') ('.\' + $stagedir)

Write-Output '#Clear staging directory'
Remove-Item -Path $stagedir -Force -Recurse