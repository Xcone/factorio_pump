$version = (Get-Content version.txt)
$mod = 'pump_' + $version
$stagedir = '.build\' + $mod
$stagedirInfoJson = $stagedir + '\info.json'

echo 'Clear the build dir'
Remove-Item -Path .build -Force -Recurse | Out-Null

echo 'Copy content to staging directory'
New-Item -ItemType "directory" -Path $stagedir | Out-Null
Copy-Item mod\* -Destination $stagedir -Recurse | Out-Null

echo 'Apply version'
(Get-Content $stagedirInfoJson).replace('<%version%>', $version) | Set-Content $stagedirInfoJson

echo 'Bundle'
Compress-Archive $stagedir ('.build\' + $mod + '.zip')

echo 'Clear staging directory'
Remove-Item -Path $stagedir -Force -Recurse
