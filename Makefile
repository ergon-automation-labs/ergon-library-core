SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)

.PHONY: test-handlers test-stores test-nats test-integration test-full setup help deps test dialyzer coverage check format clean setup-hooks logs push-and-publish compile

## Show this help message
help:
	@echo "BotArmyCore - Elixir Library"
	@echo ""
	@echo "Available commands:"
	@echo "  make setup        - Set up project (deps.get + install git hooks)"
	@echo "  make setup-hooks  - Install git hooks for pre-push validation"
	@echo "  make test         - Run all tests"
	@echo "  make credo        - Run linter (code style)"
	@echo "  make dialyzer     - Run static analysis"
	@echo "  make coverage     - Run tests with coverage"
	@echo "  make check        - Run all checks (test, credo, dialyzer)"
	@echo "  make format       - Format Elixir code"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make logs         - Tail bot_army_core log with grc (brew install grc; make -C .. install-grc)"
	@echo ""

## Initial setup
setup: init deps setup-hooks
	@echo "Setup complete. Run 'make check' to verify everything works."

## Install git hooks
setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "✓ Git hooks installed (core.hooksPath = git-hooks)"

## Initialize git repository (idempotent)
init:
	@if [ ! -d .git ]; then \
		git init; \
		echo "Git repository initialized."; \
	else \
		echo "Git repository already exists."; \
	fi

## Install dependencies
compile:
	@LOG_FILE="/tmp/compile-core-$$(date +%s).log"; \
	echo "Compiling core and logging to $$LOG_FILE..."; \
	$(MIX) compile 2>&1 | tee "$$LOG_FILE"; \
	echo "✓ Compilation log: $$LOG_FILE"

deps:
	mix deps.get

## Run all tests
compile:
	@LOG_FILE="/tmp/compile-core-$$(date +%s).log"; \
	echo "Compiling core and logging to $$LOG_FILE..."; \
	$(MIX) compile 2>&1 | tee "$$LOG_FILE"; \
	echo "✓ Compilation log: $$LOG_FILE"

test:
	mix test

test-handlers:
	MIX_ENV=test mix test --only handlers --trace

test-stores:
	MIX_ENV=test mix test --only stores --trace

test-nats:
	MIX_ENV=test mix test --only nats --trace

test-integration:
	mix test --include integration --trace

test-full:
	mix test --include integration --include nats_live --trace

## Run static analysis
dialyzer: deps
	mix dialyzer

## Run tests with coverage reporting
coverage:
	mix coveralls --umbrella

## Run all checks
check: test credo dialyzer
	@echo "All checks passed!"

## Format Elixir code
format:
	mix format

## Clean build artifacts
clean:
	mix clean
	rm -rf _build cover doc


push-and-publish: git-push
	@$(MAKE) publish-release

logs:
	@$(SCRIPTS_DIRECTORY)/tail_bot_log.sh

# Shared targets (push, credo, pre-push-cleanup, bump-version, git-push).
# Defined once in bot_army_infra so they cannot drift per repo.
BOT_ARMY_COMMON_MK := $(abspath $(CURDIR)/../bot_army_infra/make/common.mk)
ifeq ($(wildcard $(BOT_ARMY_COMMON_MK)),)
$(warning bot_army_infra not found at $(BOT_ARMY_COMMON_MK) - shared targets unavailable)
else
include $(BOT_ARMY_COMMON_MK)
endif
