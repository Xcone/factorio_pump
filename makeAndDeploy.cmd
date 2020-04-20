powershell.exe -file "make.ps1"

del %appdata%\Factorio\mods\pump_*.*.*.zip
copy .build\*.zip %appdata%\Factorio\mods\