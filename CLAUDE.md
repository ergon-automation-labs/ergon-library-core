# CLAUDE.md

This file provides guidance to Claude Code when working with `bot_army_core`.

---

## Purpose

**bot_army_core** is the shared Elixir library foundation for the Bot Army ecosystem. It provides:

- NATS message envelope handling and decoding (`BotArmyCore.NATS.Decoder`)
- Integration with core schemas (from `bot_army_schemas` at `/etc/bot_army/schemas/core/`)
- Shared error and acknowledgment response shapes
- System health and alert handling

This is executable library code that every bot depends on.

---

## File Organization

```
.
├── lib/
│   ├── bot_army_core.ex                    # Main module and docs
│   ├── bot_army_core/
│   │   ├── application.ex                  # Application supervisor
│   │   └── nats/
│   │       └── decoder.ex                  # Message envelope decoding
├── test/
│   ├── test_helper.exs
│   └── bot_army_core/
│       └── nats/
│           └── decoder_test.exs
├── mix.exs                                 # Project configuration
├── CLAUDE.md                               # This file
└── README.md
```

What does **NOT** live here:
- Per-bot message schemas (those live in `bot_army_schemas_<bot>`)
- Bot-specific business logic
- Core schema definitions (those live in `bot_army_schemas`)
- Infrastructure/deployment code (that lives in `bot_army_infra`)

---

## Development Commands

Install dependencies (one-time):
```bash
mix deps.get
```

Run tests:
```bash
mix test
```

Run linting:
```bash
mix credo
```

Run all checks:
```bash
mix test && mix credo
```

---

## Core Principles

**1. Dependency on schemas**

This library reads schema files deployed at `/etc/bot_army/schemas/core/` at runtime.

- In development: Schemas may not be available — tests should handle this gracefully
- In production: Schemas are always deployed first before this code is deployed

See `BotArmyCore.NATS.Decoder.load_schema/1` for schema loading.

**2. Message envelope is immutable**

The NATS message envelope structure (as defined in `bot_army_schemas/schemas/envelope.json`) is immutable. Never change it here — it's a contract every node depends on.

**3. Backward compatibility**

When adding features:
- New functions should be additive (don't break existing code)
- When changing existing behavior, ensure older versions can still decode messages from older nodes
- See `bot_army_schemas/docs/versioning.md` for schema versioning rules

**4. Testing**

- Unit tests in `test/bot_army_core/` mirror the module structure
- Use ExUnit for testing
- Mock schema files or skip file-system tests where appropriate for CI/CD

---

## Dependencies

Current dependencies (from `mix.exs`):

**Runtime:**
- `httpoison` - HTTP client
- `jason` - JSON encoding/decoding
- `logger_json` - JSON logging
- `ex_json_schema` - Schema validation (optional)

**Development/Test:**
- `ex_doc` - Documentation
- `credo` - Linting
- `dialyxir` - Static analysis
- `excoveralls` - Code coverage

Keep dependencies minimal and well-justified. New dependencies require approval.

---

## Deployment

This library is deployed via Salt by `bot_army_infra`. See that repo for:
- How this library is packaged
- Deployment order relative to schemas and bots
- Release management

**Important Deployment Order:**
1. Deploy schema changes to `bot_army_schemas` first
2. Deploy `bot_army_core` with updated decoders
3. Deploy bot implementations that depend on `bot_army_core`

---

## Related Repositories

- `bot_army_schemas` — Core message contract definitions
- `bot_army_infra` — Salt states and deployment
- `bot_army_schemas_<bot>` — Per-bot schemas (depend on `bot_army_schemas`)
- Individual bots (depend on `bot_army_core` and `bot_army_schemas`)

See `bot_army_repo_structure_1.md` in `bot_army_schemas` for the full polyrepo context.
