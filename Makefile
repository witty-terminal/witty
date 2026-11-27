V ?= v
VFLAGS ?= -cc clang
export VFLAGS

.PHONY: install
install:
	bash .github/scripts/install-ui2.sh
	"$(V)" -path "$(CURDIR)|@vlib|@vmodules" run tools/build install
