# RISC OS Clock — analogue tribute (Free Pascal)
#
# macOS:   make
# Linux:   sudo apt install fpc libgtk2.0-dev   &&  make linux
# Windows: from a native FPC install:            make windows

FPC      ?= fpc
SRC      := src
BUILD    := build
APP      := $(BUILD)/RISCOSClock.app
UNITS    := -Fu$(SRC) -FU$(BUILD) -FE$(BUILD)
FLAGS    := -Mobjfpc -Scgi -O2 -Xs

.PHONY: all app run linux windows test snap clean

all: app

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/RISCOSClock: $(BUILD) $(SRC)/*.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/RISCOSClock $(SRC)/clock.pas

$(BUILD)/clocktest: $(BUILD) $(SRC)/uclockmodel.pas $(SRC)/clocktest.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/clocktest $(SRC)/clocktest.pas

$(BUILD)/clocksnap: $(BUILD) $(SRC)/uclockmodel.pas $(SRC)/uclockrender.pas $(SRC)/uclockapp.pas $(SRC)/clocksnap.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/clocksnap $(SRC)/clocksnap.pas

app: $(BUILD)/RISCOSClock
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BUILD)/RISCOSClock $(APP)/Contents/MacOS/RISCOSClock
	cp bundle/Info.plist $(APP)/Contents/Info.plist

run: app
	open $(APP)

linux: $(BUILD)
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/riscosclock $(SRC)/clock.pas

windows: $(BUILD)
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/RISCOSClock.exe $(SRC)/clock.pas

test: $(BUILD)/clocktest
	$(BUILD)/clocktest

snap: $(BUILD)/clocksnap
	$(BUILD)/clocksnap $(BUILD)

clean:
	rm -rf $(BUILD)
