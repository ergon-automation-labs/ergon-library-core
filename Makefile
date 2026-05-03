SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)

.PHONY: test-handlers test-stores test-nats test-integration test-full setup help deps test credo dialyzer coverage check format clean setup-hooks logs push-and-publish

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
deps:
	mix deps.get

## Run all tests
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

## Run linter
credo:
	mix credo

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

push-and-publish:
	@git push && $(MAKE) publish-release

logs:
	@$(SCRIPTS_DIRECTORY)/tail_bot_log.sh
