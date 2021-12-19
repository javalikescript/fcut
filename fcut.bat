@ECHO OFF
SETLOCAL

set LUA_PATH=lua\?.lua
set LUA_CPATH=bin\?.dll
set WEBVIEW_WIN32_ICON=htdocs\favicon.ico
bin\lua fcut.lua -ffmpeg ffmpeg\ffmpeg.exe

ENDLOCAL
