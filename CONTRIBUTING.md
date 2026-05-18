# Contributing

## Development Setup

1. Clone the repository
2. Install Elixir 1.14+
3. Run `mix deps.get`

## Running Tests

```bash
# Unit tests (fast)
mix test

# Specific test file
mix test test/bot_army_core/handler_test.exs

# With coverage
mix test --cover
```

## Code Quality

```bash
# Lint
mix credo --strict

# Type check
mix dialyzer

# Format
mix format
```

## Adding New Patterns

When adding new patterns to bot_army_core:

1. **Design for simplicity**: The pattern should be obvious to beginners
2. **Provide examples**: Include usage examples in documentation
3. **Write comprehensive tests**: Test both success and failure cases
4. **Update architecture docs**: Document the pattern and why it exists

## Pull Request Checklist

- [ ] Tests pass: `mix test --include integration`
- [ ] Code quality: `mix credo --strict && mix dialyzer`
- [ ] Formatted: `mix format`
- [ ] Documentation updated
- [ ] CHANGELOG updated
