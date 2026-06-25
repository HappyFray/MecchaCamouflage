NATIVE_APPLY_MODE ?= artist_template_brush_paint
ARTIST_DEBUG_RUNS ?= 1
ARTIST_DEBUG_DELAY ?= 2
ARTIST_DEBUG_TIMEOUT ?= 300
VERSION ?= 1.0.0
BUILD_PS := scripts/build_runtime.ps1
RUN_PS := scripts/dev_flow.ps1
DUMPER_PS := scripts/dumper7_flow.ps1
PACKAGE_PS := scripts/package_release.ps1
ARTIST_DEBUG_PS := scripts/artist_trace_debug.ps1

.PHONY: build run artist-debug sdk-dump package clean

define RUN_POWERSHELL
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoProfile -ExecutionPolicy Bypass -File $(1) $(2); \
	elif command -v powershell.exe >/dev/null 2>&1; then \
		PS_SCRIPT_WIN="$$(if command -v wslpath >/dev/null 2>&1; then wslpath -w $(1); else printf '%s' $(1); fi)"; \
		powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$PS_SCRIPT_WIN" $(2); \
	else \
		echo "PowerShell runtime not found." >&2; exit 127; \
	fi
endef

build:
	$(call RUN_POWERSHELL,$(BUILD_PS),)

run: build
	$(call RUN_POWERSHELL,$(RUN_PS),-RuntimeArgString "--mode service --native-apply-mode $(NATIVE_APPLY_MODE)")

artist-debug: build
	$(call RUN_POWERSHELL,$(ARTIST_DEBUG_PS),-Runs $(ARTIST_DEBUG_RUNS) -DelaySeconds $(ARTIST_DEBUG_DELAY) -ApplyTimeoutSeconds $(ARTIST_DEBUG_TIMEOUT))

sdk-dump: build
	$(call RUN_POWERSHELL,$(DUMPER_PS),-BuildDumper -WaitForProcess)

package: build
	$(call RUN_POWERSHELL,$(PACKAGE_PS),-Version $(VERSION))

clean:
	rm -rf .build
