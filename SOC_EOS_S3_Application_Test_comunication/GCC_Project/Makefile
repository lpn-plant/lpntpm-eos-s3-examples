#
# Makefile for QORC SDK
#


# for all targets, check whether the QORC SDK environment has been setup first.
ifndef QORC_SDK_PATH
$(info )
$(info QORC_SDK_PATH is not set in the environment, is the QORC SDK initialized?)
$(info initialize with: 'source envsetup.sh' from the QORC SDK directory in the current shell)
$(info )
$(error QORC_SDK_PATH not defined)
endif


include config.mk

VPATH:=$(OUTPUT_PATH)

all: _makedirs_ external_srcs appdir appfpga
	-${HIDE}$(RM) $(OUTPUT_PATH)$(DIR_SEP)bin$(DIR_SEP)$(OUTPUT_FILE).*
	make -f makefiles/Makefile_output
	-${HIDE}$(MKDIR) $(OUTPUT_PATH)$(DIR_SEP)bin
	@echo Copy output files ...
	${HIDE}$(CP) $(OUTPUT_PATH)$(DIR_SEP)$(OUTPUT_FILE).bin $(OUTPUT_PATH)$(DIR_SEP)bin
	${HIDE}$(CP) $(OUTPUT_PATH)$(DIR_SEP)$(OUTPUT_FILE).map $(OUTPUT_PATH)$(DIR_SEP)bin
	${HIDE}$(CP) $(OUTPUT_PATH)$(DIR_SEP)$(OUTPUT_FILE).elf $(OUTPUT_PATH)$(DIR_SEP)bin

_makedirs_:
	@-$(MKDIR) $(DEPEND_PATH)
	@-$(MKDIR) $(OUTPUT_PATH)


.PHONY: _makedirs_


.PHONY: external_srcs
external_srcs: Startup HAL FreeRTOS Libraries BSP
	@echo "External sources built"

.PHONY: appfpga
appfpga:
	make -f makefiles/Makefile_appfpga
clean_appfpga:
	make -f makefiles/Makefile_appfpga clean
	
CLEAN_TARGET += appfpga

.PHONY: appdir
appdir:
	make -f makefiles/Makefile_appdir
clean_appdir:
	make -f makefiles/Makefile_appdir clean

CLEAN_TARGET += appdir

.PHONY:Startup
Startup:
	make -f makefiles/Makefile_Startup
clean_Startup:
	make -f makefiles/Makefile_Startup clean

CLEAN_TARGET += Startup

.PHONY:HAL
HAL:
	make -f makefiles/Makefile_HAL
clean_HAL:
	make -f makefiles/Makefile_HAL clean

CLEAN_TARGET += HAL

.PHONY:CLI
CLI:
	make -f makefiles/Makefile_cli
clean_CLI:
	make -f makefiles/Makefile_cli clean

CLEAN_TARGET += CLI

FreeRTOS:
	make -f makefiles/Makefile_FreeRTOS
clean_FreeRTOS:
	make -f makefiles/Makefile_FreeRTOS clean

CLEAN_TARGET += FreeRTOS

.PHONY:BSP
BSP:
	make -f makefiles/Makefile_quickfeather_BSP
clean_BSP:
	make -f makefiles/Makefile_quickfeather_BSP clean

CLEAN_TARGET += BSP

.PHONY:Libraries
Libraries:
	make -f makefiles/Makefile_Libraries
clean_Libraries:
	make -f makefiles/Makefile_Libraries clean

CLEAN_TARGET += Libraries


DELETEME=
DELETEME += $(wildcard $(OUTPUT_PATH)$(DIR_SEP)bin$(DIR_SEP)$(OUTPUT_FILE).*)
DELETEME += $(wildcard $(OUTPUT_PATH)$(DIR_SEP)*.o)
DELETEME += $(wildcard $(DEPEND_PATH)$(DIR_SEP)*.d)
DELETEME := $(strip $(DELETEME))
# Clean
clean: $(CLEAN_TARGET:%=clean_%)
	make -f makefiles/Makefile_output clean
ifneq (,$(DELETEME))
	-$(HIDE)$(RM) $(DELETEME)
endif



