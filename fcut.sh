#!/bin/sh
LUA_PATH="lua/?.lua" LUA_CPATH="bin/?.so" bin/lua fcut.lua -ffmpeg /usr/bin/ffmpeg "$@"
