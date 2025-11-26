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
SOURCES		:=	source
DATA		:=	data
INCLUDES	:=	include
APP_TITLE	:=  Ultrahand Reload
APP_AUTHOR	:=  ppkantorski
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

BUILDING_NRO_DIRECTIVE := 0
CFLAGS += -DBUILDING_NRO_DIRECTIVE=$(BUILDING_NRO_DIRECTIVE)

CXXFLAGS	:= $(CFLAGS) -fno-rtti -fno-exceptions
ASFLAGS	:=	-g $(ARCH)

LDFLAGS	=	-specs=$(DEVKITPRO)/libnx/switch.specs -g $(ARCH) \
			-Wl,-Map,$(notdir $*.map) -Wl,--gc-sections

LIBS	:= -lnx

LIBDIRS	:= $(PORTLIBS) $(LIBNX)

#---------------------------------------------------------------------------------
ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------

export OUTPUT	:=	$(CURDIR)/$(TARGET)
export TOPDIR	:=	$(CURDIR)
export VPATH	:=	$(foreach dir,$(SOURCES),$(CURDIR)/$(dir)) \
			$(foreach dir,$(DATA),$(CURDIR)/$(dir))
export DEPSDIR	:=	$(CURDIR)/$(BUILD)

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
export BUILDING_NRO_DIRECTIVE

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



.PHONY: $(BUILD) clean all dist

#---------------------------------------------------------------------------------
all: $(BUILD)

$(BUILD):
	@[ -d $@ ] || mkdir -p $@
	@$(MAKE) --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile
ifeq ($(BUILDING_NRO_DIRECTIVE),1)
	@echo "NRO build complete!"
else
	@echo "Creating sys-module package..."
	@rm -rf out/
	@mkdir -p out/atmosphere/contents/420000000007E51B/flags
	@cp $(CURDIR)/$(TARGET).nsp out/atmosphere/contents/420000000007E51B/exefs.nsp
	@echo "Sys-module package created in out/"
endif

#---------------------------------------------------------------------------------
clean:
	@echo clean ...
	@rm -fr $(BUILD) $(TARGET).nsp $(TARGET).nso $(TARGET).npdm $(TARGET).elf $(TARGET).nacp $(TARGET).nro
	@rm -rf out/
	@rm -f $(TARGET).zip

#---------------------------------------------------------------------------------
dist: all
	@echo making dist ...
	@rm -f $(TARGET).zip
ifeq ($(BUILDING_NRO_DIRECTIVE),1)
	@echo "Warning: dist target is for sys-module builds (BUILDING_NRO_DIRECTIVE=0)"
else
	@cd out; zip -r ../$(TARGET).zip ./*; cd ../
	@echo "Distribution package created: $(TARGET).zip"
endif

#---------------------------------------------------------------------------------
else
.PHONY:	all

DEPENDS	:=	$(OFILES:.o=.d)

#---------------------------------------------------------------------------------
# Conditional build based on BUILDING_NRO_DIRECTIVE
#---------------------------------------------------------------------------------
ifeq ($(BUILDING_NRO_DIRECTIVE),1)
# NRO-only build
all	:	$(OUTPUT).nro

$(OUTPUT).nacp:
	@echo "Creating NACP with metadata..."
	@nacptool --create "$(APP_TITLE)" "$(APP_AUTHOR)" "$(APP_VERSION)" $@

$(OUTPUT).nro: $(OUTPUT).elf $(OUTPUT).nacp
	@echo "Building $(OUTPUT).nro..."
	@elf2nro $< $@ --nacp=$(OUTPUT).nacp --icon=$(TOPDIR)/$(APP_ICON)
	@mv $(OUTPUT).nro ../Ultrahand-Reload.nro

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
