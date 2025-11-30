#---------------------------------------------------------------------------------
.SUFFIXES:
#---------------------------------------------------------------------------------

ifeq ($(strip $(DEVKITPRO)),)
$(error "Please set DEVKITPRO in your environment. export DEVKITPRO=<path to>/devkitpro")
endif

TOPDIR ?= $(CURDIR)
include $(DEVKITPRO)/libnx/switch_rules

#---------------------------------------------------------------------------------
TARGET		:=	ovlr
BUILD		:=	build
BUILD_NRO	:=	build_nro
SOURCES		:=	source
DATA		:=	data
INCLUDES	:=	include
APP_TITLE	:=  Ultrahand_Reload
APP_AUTHOR	:=	ppkantorski
APP_VERSION	:=	1.0.0
APP_ICON	:=	icon.jpg
#NO_ICON := 1

#---------------------------------------------------------------------------------
# options for code generation
#---------------------------------------------------------------------------------
ARCH	:=	-march=armv8-a+crc+crypto -mtune=cortex-a57 -mtp=soft -fPIE

CFLAGS	:=	-g -Wall -Os -ffunction-sections -fdata-sections \
			-ffast-math -fomit-frame-pointer -fno-stack-protector \
			-flto -ffat-lto-objects \
            -fuse-linker-plugin -finline-small-functions \
            -fno-strict-aliasing -frename-registers -falign-functions=16 \
			$(ARCH) $(DEFINES)

CFLAGS	+=	$(INCLUDE) -D__SWITCH__ -DVERSION=\"v$(APP_VERSION)\"

BUILDING_NRO_DIRECTIVE ?= 0
CFLAGS += -DBUILDING_NRO_DIRECTIVE=$(BUILDING_NRO_DIRECTIVE)

CXXFLAGS	:= $(CFLAGS) -fno-rtti -fno-exceptions
ASFLAGS	:=	-g $(ARCH)

LDFLAGS	=	-specs=$(DEVKITPRO)/libnx/switch.specs -g $(ARCH) \
			-Wl,-Map,$(notdir $*.map) -Wl,--gc-sections

LIBS	:= -lnx

LIBDIRS	:= $(PORTLIBS) $(LIBNX)

#---------------------------------------------------------------------------------
# Check if we're in the top-level directory or a build directory
#---------------------------------------------------------------------------------
ifeq ($(notdir $(CURDIR)),$(BUILD))
    IN_BUILD_DIR := 1
else ifeq ($(notdir $(CURDIR)),$(BUILD_NRO))
    IN_BUILD_DIR := 1
else
    IN_BUILD_DIR := 0
endif

ifneq ($(IN_BUILD_DIR),1)
#---------------------------------------------------------------------------------
# Top-level directory - set up recursive make
#---------------------------------------------------------------------------------

export TOPDIR	:=	$(CURDIR)
export VPATH	:=	$(foreach dir,$(SOURCES),$(CURDIR)/$(dir)) \
			$(foreach dir,$(DATA),$(CURDIR)/$(dir))

CFILES		:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.c)))
CPPFILES	:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.cpp)))
SFILES		:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.s)))
BINFILES	:=	$(foreach dir,$(DATA),$(notdir $(wildcard $(dir)/*.*)))

ifeq ($(strip $(CPPFILES)),)
	export LD	:=	$(CC)
else
	export LD	:=	$(CXX)
endif

export OFILES_BIN	:=	$(addsuffix .o,$(BINFILES))
export OFILES_SRC	:=	$(CPPFILES:.cpp=.o) $(CFILES:.c=.o) $(SFILES:.s=.o)
export OFILES 		:=	$(OFILES_BIN) $(OFILES_SRC)
export HFILES_BIN	:=	$(addsuffix .h,$(subst .,_,$(BINFILES)))

export INCLUDE	:=	$(foreach dir,$(INCLUDES),-I$(CURDIR)/$(dir)) \
			$(foreach dir,$(LIBDIRS),-I$(dir)/include) \
			-I$(CURDIR)/$(BUILD)
export LIBPATHS	:=	$(foreach dir,$(LIBDIRS),-L$(dir)/lib)

export APP_TITLE
export APP_AUTHOR
export APP_VERSION
export APP_ICON

ifeq ($(strip $(CONFIG_JSON)),)
	jsons := $(wildcard *.json)
	ifneq (,$(findstring $(TARGET).json,$(jsons)))
		export APP_JSON := $(TOPDIR)/$(TARGET).json
	else
		ifneq (,$(findstring config.json,$(jsons)))
			export APP_JSON := $(TOPDIR)/config.json
		endif
	endif
else
	export APP_JSON := $(TOPDIR)/$(CONFIG_JSON)
endif

.PHONY: all clean dist sysmodule nro

#---------------------------------------------------------------------------------
all: sysmodule nro
	@echo "Build complete!"

sysmodule:
	@echo "Building sys-module..."
	@[ -d $(BUILD) ] || mkdir -p $(BUILD)
	@$(MAKE) --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile BUILDING_NRO_DIRECTIVE=0 DEPSDIR=$(CURDIR)/$(BUILD) OUTPUT=$(CURDIR)/$(BUILD)/$(TARGET)
	@echo "Creating sys-module package..."
	@rm -rf out/atmosphere
	@mkdir -p out/atmosphere/contents/420000000007E51B
	@cp $(BUILD)/$(TARGET).nsp out/atmosphere/contents/420000000007E51B/exefs.nsp
	@cp toolbox.json out/atmosphere/contents/420000000007E51B/
	@echo "Sys-module package created in out/atmosphere/"

nro:
	@echo "Building NRO..."
	@[ -d $(BUILD_NRO) ] || mkdir -p $(BUILD_NRO)
	@$(MAKE) --no-print-directory -C $(BUILD_NRO) -f $(CURDIR)/Makefile BUILDING_NRO_DIRECTIVE=1 DEPSDIR=$(CURDIR)/$(BUILD_NRO) OUTPUT=$(CURDIR)/$(BUILD_NRO)/$(TARGET)
	@echo "Creating NRO package..."
	@mkdir -p out/switch/Ultrahand-Reload
	@cp $(BUILD_NRO)/$(TARGET).nro out/switch/Ultrahand-Reload/Ultrahand-Reload.nro
	@echo "NRO package created in out/switch/Ultrahand-Reload/"

#---------------------------------------------------------------------------------
clean:
	@echo clean ...
	@rm -fr $(BUILD) $(BUILD_NRO) $(TARGET).nsp $(TARGET).nso $(TARGET).npdm $(TARGET).elf $(TARGET).nacp $(TARGET).nro
	@rm -rf out/
	@rm -f $(APP_TITLE).zip

#---------------------------------------------------------------------------------
dist: all
	@echo making dist ...
	@rm -f $(APP_TITLE).zip
	@cd out; zip -r ../$(APP_TITLE).zip ./*; cd ../
	@echo "Distribution package created: $(APP_TITLE).zip"

#---------------------------------------------------------------------------------
else
#---------------------------------------------------------------------------------
# Inside build directory - do actual compilation
#---------------------------------------------------------------------------------

.PHONY: all

export DEPSDIR
DEPENDS	:=	$(OFILES:.o=.d)

#---------------------------------------------------------------------------------
# Conditional build based on BUILDING_NRO_DIRECTIVE
#---------------------------------------------------------------------------------
ifeq ($(BUILDING_NRO_DIRECTIVE),1)
# NRO build
all	:	$(OUTPUT).nro

$(OUTPUT).nacp:
	@echo "Creating NACP with metadata..."
	@nacptool --create "$(APP_TITLE)" "$(APP_AUTHOR)" "$(APP_VERSION)" $@

$(OUTPUT).nro: $(OUTPUT).elf $(OUTPUT).nacp
	@echo "Building $(OUTPUT).nro..."
	@elf2nro $< $@ --nacp=$(OUTPUT).nacp --icon=$(TOPDIR)/$(APP_ICON)

else
# Sys-module build (NSP)
all	:	$(OUTPUT).nsp

$(OUTPUT).nsp	:	$(OUTPUT).nso $(OUTPUT).npdm

$(OUTPUT).nso	:	$(OUTPUT).elf

endif

#---------------------------------------------------------------------------------
# Common rules for both build types
#---------------------------------------------------------------------------------
$(OUTPUT).elf	:	$(OFILES)

$(OFILES_SRC)	: $(HFILES_BIN)

#---------------------------------------------------------------------------------
%.bin.o	%_bin.h :	%.bin
	@echo $(notdir $<)
	@$(bin2o)

-include $(DEPENDS)

#---------------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------------
