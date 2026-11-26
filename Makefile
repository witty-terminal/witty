V ?= v
VFLAGS ?= -cc clang
export VFLAGS

.PHONY: install
install:
ifeq ($(shell uname -s),Linux)
	bash .github/scripts/install-ui2.sh
endif
	"$(V)" -path "$(CURDIR)|@vlib|@vmodules" run tools/build install
