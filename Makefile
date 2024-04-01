LUACLIBS := ../luaclibs
LUACLIBS_DIST := $(LUACLIBS)/dist
FCUT_DIST := dist
FCUT_DIST_CLUA := $(FCUT_DIST)/bin
FCUT_DIST_LUA := $(FCUT_DIST)/lua

FCUT_REL := ../fcut

PLAT ?= $(shell grep ^platform $(LUACLIBS_DIST)/versions.txt | cut -f2)
TARGET_NAME ?= $(shell grep ^target $(LUACLIBS_DIST)/versions.txt | cut -f2)
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

RELEASE_FILES ?= fcut$(EXE) README.md licenses.txt

LUAJLS=luajls
STATIC_FLAGS_windows=lua/src/wlua.res -mwindows
STATIC_FLAGS_linux=

release: bin licenses release$(ZIP)

release-full:
	$(MAKE) release RELEASE_FILES="$(RELEASE_FILES) ffmpeg"

show:
	@echo PLAT: $(PLAT)
	@echo TARGET_NAME: $(TARGET_NAME)
	@echo RELEASE_DATE: $(RELEASE_DATE)
	@echo RELEASE_NAME: $(RELEASE_NAME)

licenses:
	cp -u $(LUACLIBS)/licenses.txt .

bin:
	$(MAKE) -C $(LUACLIBS) STATIC_OPENSSL= \
		STATIC_RESOURCES="-R $(FCUT_REL)/assets $(FCUT_REL)/htdocs -l $(FCUT_REL)/fcut.lua $(FCUT_REL)/fcutSchema.lua $(FCUT_REL)/Ffmpeg.lua $(FCUT_REL)/FileChooser.lua" \
		LUAJLS=$(LUAJLS) STATIC_FLAGS="$(STATIC_FLAGS_$(PLAT))" STATIC_EXECUTE="require('fcut')" STATIC_NAME=fcut static-full
	mv $(LUACLIBS)/dist/fcut$(EXE) .

release.tar.gz:
	-rm -f fcut$(RELEASE_NAME).tar.gz
	tar --group=jls --owner=jls -zcvf fcut$(RELEASE_NAME).tar.gz $(RELEASE_FILES)

release.zip:
	-rm -f fcut$(RELEASE_NAME).zip
	zip -r fcut$(RELEASE_NAME).zip $(RELEASE_FILES)
