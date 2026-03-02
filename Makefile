.PHONY: setup help deps test credo dialyzer coverage check format clean

## Show this help message
help:
	@echo "BotArmyCore - Elixir Library"
	@echo ""
	@echo "Available commands:"
	@echo "  make setup        - Set up project (deps.get)"
	@echo "  make test         - Run all tests"
	@echo "  make credo        - Run linter (code style)"
	@echo "  make dialyzer     - Run static analysis"
	@echo "  make coverage     - Run tests with coverage"
	@echo "  make check        - Run all checks (test, credo, dialyzer)"
	@echo "  make format       - Format Elixir code"
	@echo "  make clean        - Clean build artifacts"
	@echo ""

## Initial setup
setup: init deps
	@echo "Setup complete. Run 'make check' to verify everything works."

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
