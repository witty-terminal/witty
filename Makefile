V ?= v
VFLAGS ?= -cc clang
export VFLAGS

.PHONY: install
install:
	"$(V)" -path "$(CURDIR)|@vlib|@vmodules" run tools/build install -Doptimize=ReleaseFast
