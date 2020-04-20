$version = (Get-Content version.txt)
$mod = 'pump_' + $version
$stagedir = '.build\' + $mod
$stagedirInfoJson = $stagedir + '\info.json'
$7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

echo '#Clear the build dir'
Remove-Item -Path .build -Force -Recurse

echo '#Copy content to staging directory'
New-Item -ItemType "directory" -Path $stagedir
Copy-Item mod\* -Destination $stagedir -Recurse

echo '#Apply version'
(Get-Content $stagedirInfoJson).replace('<%version%>', $version) | Set-Content $stagedirInfoJson

echo '#Bundle'
if (-not (Test-Path -Path $7zipPath -PathType Leaf)) {
    throw "7 zip file '$7zipPath' not found"
}
& $7zipPath a -tzip ('.build\' + $mod + '.zip') ('.\' + $stagedir)

echo '#Clear staging directory'
Remove-Item -Path $stagedir -Force -Recurse