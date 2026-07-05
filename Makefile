# Brutalium — Makefile
#
# Targets:
#   make               build the injection dylib and the CLI
#   sudo make install  install dylib + CLI + blacklist + LaunchAgent
#   sudo make uninstall

ifeq (,$(filter help,$(MAKECMDGOALS)))
  CC      := $(shell xcrun -find clang)
  SDKROOT ?= $(shell xcrun --show-sdk-path)
else
  CC      := clang
  SDKROOT :=
endif

PROJECT     = Brutalium
DYLIB_NAME  = lib$(PROJECT).dylib
CLI_NAME    = brutalium

BUILD_DIR   = build
SRC_DIR     = src
APP_DIR     = app
INSTALL_DIR = /var/ammonia/core/tweaks
CLI_DIR     = /usr/local/bin
AGENT_DIR   = /Library/LaunchAgents
AGENT       = com.tweak.brutalium.publish.plist

# Injected code must cover arm64e for modern system processes.
TWEAK_ARCHS = -arch x86_64 -arch arm64 -arch arm64e

CFLAGS = -Wall -Wextra -O2 -fobjc-arc \
         -isysroot $(SDKROOT) \
         -iframework $(SDKROOT)/System/Library/Frameworks \
         -F/System/Library/PrivateFrameworks \
         -I$(SRC_DIR) -IZKSwizzle

FRAMEWORKS = -framework Foundation -framework AppKit \
             -framework QuartzCore -framework CoreFoundation

DYLIB_SOURCES = $(SRC_DIR)/Brutalium.m $(SRC_DIR)/BRWindows.m $(SRC_DIR)/BRLights.m $(SRC_DIR)/BRTint.m $(SRC_DIR)/BRGlass.m $(SRC_DIR)/BRTitlebar.m ZKSwizzle/ZKSwizzle.m
CLI_SOURCE    = $(SRC_DIR)/clitool.m

DYLIB_FLAGS = -dynamiclib -install_name @rpath/$(DYLIB_NAME) \
              -compatibility_version 1.0.0 -current_version 1.0.0

BLACKLIST_SRC  = lib$(PROJECT).dylib.blacklist
BLACKLIST_DEST = $(INSTALL_DIR)/$(BLACKLIST_SRC)

.PHONY: all clean install uninstall help

all: clean $(BUILD_DIR)/$(DYLIB_NAME) $(BUILD_DIR)/$(CLI_NAME) ## Build everything

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/$(DYLIB_NAME): | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TWEAK_ARCHS) $(DYLIB_FLAGS) $(DYLIB_SOURCES) -o $@ \
		-F/System/Library/PrivateFrameworks $(FRAMEWORKS)

$(BUILD_DIR)/$(CLI_NAME): | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TWEAK_ARCHS) $(CLI_SOURCE) \
		-framework Foundation -framework CoreFoundation -o $@

install: all ## Install dylib + CLI + blacklist + LaunchAgent
	sudo mkdir -p $(INSTALL_DIR) $(CLI_DIR)
	sudo install -m 755 $(BUILD_DIR)/$(DYLIB_NAME) $(INSTALL_DIR)
	sudo install -m 755 $(BUILD_DIR)/$(CLI_NAME) $(CLI_DIR)
	@if [ -f $(BLACKLIST_SRC) ]; then \
		sudo install -m 644 $(BLACKLIST_SRC) $(BLACKLIST_DEST); \
	fi
	@sudo install -m 644 $(APP_DIR)/$(AGENT) $(AGENT_DIR)/ 2>/dev/null || true
	@echo "Installed $(DYLIB_NAME) and $(CLI_NAME)."
	@echo "Ammonia injects at launch — relaunch apps to see the changes."
	@echo "Run 'brutalium publish' (or log out/in) so sandboxed apps pick up settings."

uninstall: ## Remove installed files
	sudo rm -f $(INSTALL_DIR)/$(DYLIB_NAME)
	sudo rm -f $(CLI_DIR)/$(CLI_NAME)
	sudo rm -f $(BLACKLIST_DEST)
	sudo rm -f $(AGENT_DIR)/$(AGENT)
	@echo "Uninstalled $(PROJECT)."

clean: ## Remove build artifacts
	@rm -rf $(BUILD_DIR)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*## "}{printf "  %-12s %s\n", $$1, $$2}'
