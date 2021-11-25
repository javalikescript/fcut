@ECHO OFF
SETLOCAL

set LUA_PATH=lua\?.lua
set LUA_CPATH=bin\?.dll
bin\lua fcut.lua -ffmpeg ffmpeg\ffmpeg.exe

ENDLOCAL
