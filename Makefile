SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)

.PHONY: test-handlers test-stores test-nats test-integration test-full setup help deps test credo dialyzer coverage check format clean setup-hooks logs git-push push-and-publish bump-version compile

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

push: test compile credo pre-push-cleanup
	@echo "✅ All validations passed"
	@echo "$$(date +%s)" > .push-validated
	@echo "✓ Proof-of-validation created"
	@$(MAKE) git-push


git-push:
	@LOG_FILE="/tmp/git-push-bot_army_library_core-$$(date +%s).log"; \
	echo "Pushing to origin/main and logging to $$LOG_FILE..."; \
	git push 2>&1 | tee "$$LOG_FILE"; \
	echo "✓ Log saved: $$LOG_FILE"

push-and-publish: git-push
	@$(MAKE) publish-release

logs:
	@$(SCRIPTS_DIRECTORY)/tail_bot_log.sh

bump-version:
	@if [ -z "$(BUMP)" ]; then echo "Usage: make bump-version BUMP=major|minor|patch"; exit 1; fi
	@OLD=$$(grep 'version:' mix.exs | head -1 | sed -E 's/.*version: "([^"]+)".*/\1/'); \
	bash $(SCRIPTS_DIRECTORY)/bump_version.sh mix.exs $(BUMP) > /dev/null; \
	NEW=$$(grep 'version:' mix.exs | head -1 | sed -E 's/.*version: "([^"]+)".*/\1/'); \
	echo "✓ Bumped: $$OLD → $$NEW"
