del .build\*.zip
powershell Compress-Archive mod .build\pump_0.1.0.zip

del %appdata%\Factorio\mods\pump_*.*.*.zip
copy .build\* %appdata%\Factorio\mods\