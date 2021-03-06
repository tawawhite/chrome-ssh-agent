GO		?= GO15VENDOREXPERIMENT=1 go
GOPATH		:= $(firstword $(subst :, ,$(shell $(GO) env GOPATH)))

GOLINT		?= $(GOPATH)/bin/golint
GOPHERJS	?= $(GOPATH)/bin/gopherjs
pkgs		= $(shell $(GO) list ./... | grep -v /vendor/)

PREFIX		?= $(shell pwd)
BIN_DIR		?= $(PREFIX)/bin

# These are read by deploy-webstore.py, so must be exported.
export EXTENSION_ID	= eechpbnaifiimgajnomdipfaamobdfha
export EXTENSION_ZIP	= $(BIN_DIR)/chrome-ssh-agent.zip
export PUBLISH_TARGET	= default

# Finding the NPM bin directory is a bit tricky. First, attempt to locate it
# from our current working directory. If modules were installed somewhere else
# (e.g., in a global location, the user's home directory), then the returned
# path may not actually exist. (npm bin may pick up the node_modules directory
# that we create when we install the syscall module.)  If the returned directory
# does not exist, then try again but from the perspective of our parent
# directory.
NPM_BIN		= $(shell test -d $$(npm bin) && npm bin || (cd .. && npm bin))

# Finding node-gyp requires going up one level and then querying. We do not want
# to find our own node_modules directory.
NODE_GYP	= $(NPM_BIN)/node-gyp
NODE_SYSCALL	= node_modules/syscall.node

XVFB_RUN	= $(shell which xvfb-run)
MOCHA		= $(NPM_BIN)/mocha

MAKECRX		= $(BIN_DIR)/makecrx.sh
TEST_CRX_KEY	= $(BIN_DIR)/test-crx-key.pem
export TEST_EXTENSION_CRX	= $(BIN_DIR)/chrome-ssh-agent.crx
export TEST_EXTENSION_ID	= gcdecdcemcbepilaaaoljdlilamnoeob

all: format style lint vet test build zip

$(NODE_SYSCALL):
	# See https://github.com/gopherjs/gopherjs/blob/master/doc/syscalls.md
	@cd vendor/github.com/gopherjs/gopherjs/node-syscall && $(NODE_GYP) rebuild
	@mkdir -p $(shell dirname $(NODE_SYSCALL))
	@ln vendor/github.com/gopherjs/gopherjs/node-syscall/build/Release/syscall.node $(NODE_SYSCALL)

format:
	@echo ">> formatting code"
	@$(GO) fmt $(pkgs)

style:
	@echo ">> checking code style"
	@! gofmt -d $(shell find . -path ./vendor -prune -o -name '*.go' -print) | grep '^'

vet:
	@echo ">> vetting code"
	@$(GO) vet $(pkgs)

lint: $(GOLINT)
	@echo ">> linting code"
	@$(GOLINT) $(pkgs)

unit-test: $(GOPHERJS) $(NODE_SYSCALL)
	@echo ">> running unit tests"
	@$(GOPHERJS) test $(pkgs)

e2e-test: $(TEST_EXTENSION_CRX)
	@echo ">> running end-to-end tests"
	@$(XVFB_RUN) $(MOCHA) test/e2e.js

test: unit-test e2e-test

build: $(GOPHERJS)
	@echo ">> building"
	@cd go/options && $(GOPHERJS) build
	@cd go/background && $(GOPHERJS) build

$(TEST_EXTENSION_CRX): $(EXTENSION_ZIP)
	@echo ">> building Chrome extension (CRX for testing)"
	@$(MAKECRX) $(EXTENSION_ZIP) $(TEST_CRX_KEY) $(TEST_EXTENSION_CRX)

$(EXTENSION_ZIP): build
	@echo ">> building Chrome extension"
	@mkdir -p $(shell dirname $(EXTENSION_ZIP))
	@zip -qr -9 -X "${EXTENSION_ZIP}" . --include \
		manifest.json \
		\*.css \
		\*.html \
		\*.js \
		\*.png \
		\*CONTRIBUTING* \
		\*README* \
		\*LICENCE*

zip: $(EXTENSION_ZIP)

deploy-webstore: $(EXTENSION_ZIP)
	@echo ">> deploying to Chrome Web Store"
	@bin/deploy-webstore.py

$(GOPHERJS):
	@$(GO) install github.com/google/chrome-ssh-agent/vendor/github.com/gopherjs/gopherjs

$(GOLINT):
	@GOOS= GOARCH= $(GO) get -u github.com/golang/lint/golint

.PHONY: all
