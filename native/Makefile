# Build ReaProfessor REAPER extension (hookcustommenu — no reaper-menu.ini).
#
# Linux:   make
# macOS:   make OS=mac
# Windows: use GitHub Actions / MSVC (see tools/build_extension.sh)

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
SDK  := $(ROOT)/vendor/reaper-sdk
WDL  := $(ROOT)/vendor/WDL
SRC  := $(ROOT)/native/reaper_reaprofessor.cpp

CXXFLAGS ?= -O2 -fPIC -std=c++17 -fvisibility=hidden
CXXFLAGS += -I$(SDK) -I$(WDL) -I$(WDL)/swell
CXXFLAGS += -DSWELL_PROVIDED_BY_APP

OS ?= $(shell uname -s)

.PHONY: all clean install

ifeq ($(OS),Linux)
  TARGET := $(ROOT)/dist/linux64/reaper_reaprofessor-x86_64.so
  STUB   := $(WDL)/swell/swell-modstub-generic.cpp
  LDFLAGS := -shared -Wl,-soname,reaper_reaprofessor-x86_64.so
  all: $(TARGET)
  $(TARGET): $(SRC) $(STUB)
	mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $(SRC) $(STUB)
endif

ifeq ($(OS),Darwin)
  UNAME_M := $(shell uname -m)
  ifeq ($(UNAME_M),arm64)
    TARGET := $(ROOT)/dist/darwin-arm64/reaper_reaprofessor.dylib
  else
    TARGET := $(ROOT)/dist/darwin64/reaper_reaprofessor.dylib
  endif
  STUB := $(WDL)/swell/swell-modstub.mm
  LDFLAGS := -bundle -undefined dynamic_lookup
  all: $(TARGET)
  $(TARGET): $(SRC) $(STUB)
	mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $(SRC) $(STUB) -framework AppKit
endif

install: all
	@test -n "$(TARGET)" || (echo "Unsupported OS=$(OS)"; exit 1)
	mkdir -p "$(HOME)/.config/REAPER/UserPlugins"
	# macOS resource path differs; link_to_reaper.sh also copies
	cp -f "$(TARGET)" "$(HOME)/.config/REAPER/UserPlugins/" 2>/dev/null || true
	@echo "Built $(TARGET)"

clean:
	rm -rf $(ROOT)/dist/linux64 $(ROOT)/dist/darwin64 $(ROOT)/dist/darwin-arm64
