# Build, test and style gates. CI runs the same targets, so a local `make pre-commit`
# is the gate it will apply. See CONTRIBUTING.md.

SWIFT               ?= swift
BUILD_CONFIGURATION ?= debug
WARNINGS_AS_ERRORS  ?= true
SWIFT_SRC            = Sources Tests

ifeq ($(WARNINGS_AS_ERRORS),true)
SWIFT_FLAGS += -Xswiftc -warnings-as-errors
endif

.DEFAULT_GOAL := build
.PHONY: build release test fmt check swift-fmt swift-fmt-check \
        update-licenses check-licenses lint-docs pre-commit clean

build:
	$(SWIFT) build -c $(BUILD_CONFIGURATION) $(SWIFT_FLAGS)

release:
	$(MAKE) build BUILD_CONFIGURATION=release

test:
	$(SWIFT) test

## Rewrite sources in place, then apply any missing license headers.
fmt: swift-fmt update-licenses

## Verify formatting, headers and prose. Changes nothing; this is the CI gate.
check: swift-fmt-check check-licenses lint-docs

swift-fmt:
	$(SWIFT) format --recursive --configuration .swift-format -i $(SWIFT_SRC)

swift-fmt-check:
	$(SWIFT) format lint --recursive --strict --configuration .swift-format-nolint $(SWIFT_SRC)

update-licenses:
	python3 scripts/license-headers.py

check-licenses:
	python3 scripts/license-headers.py --check

## Google developer documentation style, over comments and Markdown.
lint-docs:
	vale $(SWIFT_SRC) docs *.md

pre-commit: check build test

clean:
	$(SWIFT) package clean
	rm -rf .build
