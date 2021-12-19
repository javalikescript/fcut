
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
MK_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))

ARCH = x86_64

ifeq ($(UNAME_S),Linux)
	PLAT ?= linux
else
	PLAT ?= windows
	MK_PATH := $(subst /c/,C:/,$(MK_PATH))
endif

LUACLIBS := ../luaclibs/dist-$(PLAT)
FCUT_DIST := dist

SO_windows=dll
EXE_windows=.exe
ZIP_windows=.zip

SO_linux=so
EXE_linux=
ZIP_linux=.tar.gz

SO := $(SO_$(PLAT))
EXE := $(EXE_$(PLAT))
MAIN_MK := $(MK_$(PLAT))
ZIP := $(ZIP_$(PLAT))

GCC_NAME ?= $(shell gcc -dumpmachine)
LUA_APP = $(LUACLIBS)/lua$(EXE)
LUA_DATE = $(shell $(LUA_APP) -e "print(os.date('%Y%m%d'))")
DIST_SUFFIX ?= -$(GCC_NAME).$(LUA_DATE)

WEBVIEW_ARCH = x64
ifeq (,$(findstring x86_64,$(GCC_NAME)))
  WEBVIEW_ARCH = x86
endif

main: dist-archive

show:
	@echo ARCH: $(ARCH)
	@echo PLAT: $(PLAT)
	@echo DIST_SUFFIX: $(DIST_SUFFIX)
	@echo UNAME_S: $(UNAME_S)
	@echo UNAME_M: $(UNAME_M)

dist-copy-linux:
	-cp -u $(LUACLIBS)/linux.$(SO) $(FCUT_DIST)/bin/
	cp -u fcut.sh $(FCUT_DIST)/

dist-copy-windows:
	-cp -u $(LUACLIBS)/winapi.$(SO) $(FCUT_DIST)/bin/
	-cp -u $(LUACLIBS)/win32.$(SO) $(FCUT_DIST)/bin/
	cp -u $(LUACLIBS)/lua*.$(SO) $(FCUT_DIST)/bin/
	cp -u $(LUACLIBS)/WebView2Loader.dll $(FCUT_DIST)/bin/
	cp -u fcut.bat $(FCUT_DIST)/

dist-copy: dist-copy-$(PLAT)
	cp -u $(LUACLIBS)/lua$(EXE) $(FCUT_DIST)/bin/
	cp -u $(LUACLIBS)/cjson.$(SO) $(FCUT_DIST)/bin/
	cp -u $(LUACLIBS)/luv.$(SO) $(FCUT_DIST)/bin/
	cp -u $(LUACLIBS)/zlib.$(SO) $(FCUT_DIST)/bin/
	cp -u $(LUACLIBS)/webview.$(SO) $(FCUT_DIST)/bin/
	cp -ru $(LUACLIBS)/sha1/ $(FCUT_DIST)/lua/
	cp -u $(LUACLIBS)/XmlParser.lua $(FCUT_DIST)/lua/
	cp -u $(LUACLIBS)/sha1.lua $(FCUT_DIST)/lua/
	cp -ru $(LUACLIBS)/jls/ $(FCUT_DIST)/lua/
	cp -u *.lua $(FCUT_DIST)/lua/
	mv $(FCUT_DIST)/lua/fcut.lua $(FCUT_DIST)/
	cp -ru htdocs/ $(FCUT_DIST)/
	-rm -f assets.tmp.zip
	cd assets/ && zip -r ../assets.tmp.zip *
	mv assets.tmp.zip $(FCUT_DIST)/assets.zip

dist-clean:
	rm -rf $(FCUT_DIST)

dist-prepare:
	-mkdir $(FCUT_DIST)
	mkdir $(FCUT_DIST)/bin
	mkdir $(FCUT_DIST)/lua

dist: dist-clean dist-prepare dist-copy

dist-full: dist
	-cp -ru ffmpeg/ $(FCUT_DIST)/

dist.tar.gz:
	cd $(FCUT_DIST) && tar --group=jls --owner=jls -zcvf fcut$(DIST_SUFFIX).tar.gz *

dist.zip:
	cd $(FCUT_DIST) && zip -r fcut$(DIST_SUFFIX).zip *

dist-archive: dist dist$(ZIP)

dist-full-archive: dist-full dist$(ZIP)
	mv $(FCUT_DIST)/fcut$(DIST_SUFFIX).zip $(FCUT_DIST)/fcut-ffmpeg$(DIST_SUFFIX).zip

ffmpeg.zip:
	cd ffmpeg && zip -r ../dist/ffmpeg-$(ARCH)-$(PLAT).zip *

ffmpeg-archive: ffmpeg$(ZIP)

.PHONY: dist
