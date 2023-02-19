LUACLIBS := ../luaclibs/dist
FCUT_DIST := dist
FCUT_DIST_CLUA := $(FCUT_DIST)/bin
FCUT_DIST_LUA := $(FCUT_DIST)/lua

PLAT ?= $(shell grep ^platform $(LUACLIBS)/versions.txt | cut -f2)
TARGET_NAME ?= $(shell grep ^target $(LUACLIBS)/versions.txt | cut -f2)
RELEASE_DATE = $(shell date '+%Y%m%d')
RELEASE_NAME ?= -$(TARGET_NAME).$(RELEASE_DATE)

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

main: dist-archive

show:
	@echo PLAT: $(PLAT)
	@echo TARGET_NAME: $(TARGET_NAME)
	@echo RELEASE_DATE: $(RELEASE_DATE)
	@echo RELEASE_NAME: $(RELEASE_NAME)

dist-copy-linux:
	-cp -u $(LUACLIBS)/linux.$(SO) $(FCUT_DIST_CLUA)/
	cp -u fcut.sh $(FCUT_DIST)/

dist-copy-windows:
	-cp -u $(LUACLIBS)/winapi.$(SO) $(FCUT_DIST_CLUA)/
	-cp -u $(LUACLIBS)/win32.$(SO) $(FCUT_DIST_CLUA)/
	cp -u $(LUACLIBS)/lua*.$(SO) $(FCUT_DIST_CLUA)/
	-cp -u $(LUACLIBS)/wlua$(EXE) $(FCUT_DIST_CLUA)/
	cp -u $(LUACLIBS)/WebView2Loader.dll $(FCUT_DIST_CLUA)/
	cp -u fcut.bat $(FCUT_DIST)/

dist-copy-sha1:
	cp -ru $(LUACLIBS)/sha1/ $(FCUT_DIST_LUA)/
	cp -u $(LUACLIBS)/sha1.lua $(FCUT_DIST_LUA)/

dist-make-sha1:
	mkdir $(FCUT_DIST_LUA)/sha1
	cp -u $(LUACLIBS)/../sha1/src/sha1/*.lua $(FCUT_DIST_LUA)/sha1/
	printf "return require('sha1.init')" > $(FCUT_DIST_LUA)/sha1.lua

dist-copy: dist-copy-$(PLAT) dist-make-sha1
	cp -u $(LUACLIBS)/lua$(EXE) $(FCUT_DIST_CLUA)/
	cp -u $(LUACLIBS)/cjson.$(SO) $(FCUT_DIST_CLUA)/
	cp -u $(LUACLIBS)/luv.$(SO) $(FCUT_DIST_CLUA)/
	cp -u $(LUACLIBS)/zlib.$(SO) $(FCUT_DIST_CLUA)/
	cp -u $(LUACLIBS)/webview.$(SO) $(FCUT_DIST_CLUA)/
	cp -u $(LUACLIBS)/XmlParser.lua $(FCUT_DIST_LUA)/
	cp -ru $(LUACLIBS)/jls/ $(FCUT_DIST_LUA)/
	cp -u *.lua $(FCUT_DIST_LUA)/
	mv $(FCUT_DIST_LUA)/fcut.lua $(FCUT_DIST)/
	cp -ru htdocs/ $(FCUT_DIST)/
	-rm -f assets.tmp.zip
	cd assets/ && zip -r ../assets.tmp.zip *
	mv assets.tmp.zip $(FCUT_DIST)/assets.zip

dist-clean:
	rm -rf $(FCUT_DIST)

dist-prepare:
	-mkdir $(FCUT_DIST)
	mkdir $(FCUT_DIST_CLUA)
	mkdir $(FCUT_DIST_LUA)

dist: dist-clean dist-prepare dist-copy

dist-full: dist
	-cp -ru ffmpeg/ $(FCUT_DIST)/

dist.tar.gz:
	cd $(FCUT_DIST) && tar --group=jls --owner=jls -zcvf fcut$(RELEASE_NAME).tar.gz *

dist.zip:
	cd $(FCUT_DIST) && zip -r fcut$(RELEASE_NAME).zip *

dist-archive: dist dist$(ZIP)

dist-full-archive release: dist-full dist$(ZIP)
	mv $(FCUT_DIST)/fcut$(RELEASE_NAME).zip $(FCUT_DIST)/fcut-ffmpeg$(RELEASE_NAME).zip

ffmpeg.zip:
	cd ffmpeg && zip -q -r ../dist/ffmpeg-$(ARCH)-$(PLAT).zip *

ffmpeg-archive : ffmpeg$(ZIP)

.PHONY: dist
