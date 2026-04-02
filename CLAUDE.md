# CLAUDE.md

This file provides guidance to Claude Code when working with `bot_army_core`.

---

## Purpose

**bot_army_core** is the shared Elixir library foundation for the Bot Army ecosystem. It provides:

- NATS message envelope handling and decoding (`BotArmyCore.NATS.Decoder`)
- Integration with core schemas (from `bot_army_schemas` at `/etc/bot_army/schemas/core/`)
- Shared error and acknowledgment response shapes
- System health and alert handling
- **Skill harness** (`BotArmy.GenBot` macro + `BotArmy.Skill` behaviour)
- **Knowledge graph support** (`BotArmy.Graph` module for Apache AGE queries)
- **LLM integration** (`BotArmy.LLMProxy` for NATS-based LLM calls)

This is executable library code that every bot depends on.

---

## File Organization

```
.
├── lib/
│   ├── bot_army_core.ex                    # Main module and docs
│   ├── bot_army_core/
│   │   ├── application.ex                  # Application supervisor
│   │   ├── graph_repo.ex                   # Ecto Repo for Apache AGE
│   │   ├── nats.ex                         # NATS publish/subscribe wrappers
│   │   └── nats/
│   │       └── decoder.ex                  # Message envelope decoding
│   └── bot_army/
│       ├── skill.ex                        # Skill behaviour + __using__ macro
│       ├── job.ex                          # Job behaviour for scheduled tasks
│       ├── gen_bot.ex                      # GenBot harness (GenServer macro)
│       ├── graph.ex                        # Cypher query helpers for AGE
│       ├── llm_proxy.ex                    # LLM request/reply via NATS
│       ├── default_personality.ex          # Default personality config
│       └── skills/
│           └── extract_entities.ex         # Example skill: entity extraction
├── config/
│   └── config.exs                          # GraphRepo & graph_enabled config
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

## Skill Harness & GenBot

**`BotArmy.GenBot`** is a macro that creates a GenServer harness for bots to run skills. Skills are discrete, reusable units of work triggered via NATS messages.

### Implementing a Skill

```elixir
defmodule MyBot.Skills.Summarize do
  use BotArmy.Skill

  def name, do: :summarize
  def description, do: "Summarizes text using LLM"
  def nats_triggers, do: ["mybot.command.summarize"]
  def llm_hint, do: :fast

  def execute(%{"text" => text}, ctx) do
    with {:ok, summary} <- ctx.llm.request("Summarize: " <> text, hint: llm_hint()) do
      {:ok, %{summary: summary}}
    end
  end

  def validate(%{"text" => t}) when is_binary(t) and byte_size(t) > 0, do: :ok
  def validate(_), do: {:error, "text field required"}
end
```

### Using GenBot in a Bot

```elixir
defmodule MyBot do
  use BotArmy.GenBot,
    skills: [MyBot.Skills.Summarize, MyBot.Skills.Classify],
    jobs: [MyBot.Jobs.DailyDigest],
    personality: MyBot.Personality,
    bot_id: :my_bot
end
```

**GenBot provides:**
- NATS subscription to all skill triggers and context updates
- Async skill dispatch via `Task.start/1` (non-blocking)
- Context injection: `%{bot_id, personality, context, llm: BotArmy.LLMProxy}`
- Skill success/error event publishing
- 30s heartbeat to `bot.army.health.<bot_id>`
- Overridable hooks: `on_skill_success/3`, `on_skill_error/3`
- Subscription retry with 2s backoff if NATS not ready at init

---

## Knowledge Graph (Apache AGE)

**`BotArmy.Graph`** provides Cypher query helpers for Apache AGE (graph database on PostgreSQL).

### Configuration

Enable graph support in bot config:
```elixir
config :bot_army_core, :graph_enabled, true
```

Environment variables (set by Salt):
```bash
GRAPHDB_HOST=localhost        # Default: localhost
GRAPHDB_PORT=30002            # Default: 30002
GRAPHDB_USER=postgres         # Default: postgres
GRAPHDB_PASSWORD=postgres     # Default: postgres
GRAPHDB_NAME=ergon_graphs     # Default: ergon_graphs
```

### One-Time Setup

```bash
# Connect to PostgreSQL
psql -h localhost -p 30002 -U postgres -d ergon_graphs

# In psql:
CREATE EXTENSION IF NOT EXISTS age;
SELECT create_graph('knowledge');
```

### Graph Operations

```elixir
# Upsert nodes
BotArmy.Graph.upsert_nodes([
  %{id: "alice", type: "person", name: "Alice", properties: %{email: "alice@example.com"}},
  %{id: "acme", type: "company", name: "Acme Corp", properties: %{industry: "tech"}}
])

# Upsert edges (relationships)
BotArmy.Graph.upsert_edges([
  %{from_id: "alice", to_id: "acme", type: "WORKS_AT", properties: %{since: 2024}}
])

# Execute arbitrary Cypher
BotArmy.Graph.query("MATCH (n:person) RETURN n LIMIT 10")
```

**Node types:** person, company, project, task, place

**Relationship types:** WORKS_AT, MANAGES, RELATED_TO, ASSIGNED_TO

---

## LLM Proxy

**`BotArmy.LLMProxy`** allows skills to call the LLM bot via NATS without knowledge of the protocol details.

```elixir
{:ok, result} = BotArmy.LLMProxy.request(
  "Extract entities from: " <> text,
  hint: :fast,      # :fast, :quality, :research, or :none
  timeout: 15_000   # milliseconds
)
```

The proxy:
- Generates unique `prompt_id` for correlation
- Subscribes to reply subject before publishing (race condition prevention)
- Publishes to `llm.prompt.submit` with full envelope
- Waits for matching reply on `events.llm.completion.core.skill_llm_request`
- Returns `{:ok, completion_text}` or `{:error, reason}`

---

## Dependencies

Current dependencies (from `mix.exs`):

**Runtime:**
- `httpoison` - HTTP client
- `jason` - JSON encoding/decoding
- `logger_json` - JSON logging
- `ex_json_schema` - Schema validation (optional)
- `bot_army_runtime` - NATS connection and utilities
- `ecto_sql` - Database ORM (for AGE graph queries)
- `postgrex` - PostgreSQL adapter
- `elixir_uuid` - UUID generation (for prompt_id correlation)
- `gnat` - NATS client

**Development/Test:**
- `ex_doc` - Documentation
- `credo` - Linting
- `dialyxir` - Static analysis
- `excoveralls` - Code coverage
- `mox` - Mocking for tests

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

---

## Agent Workflow Pattern

**Effective use of Claude Code agents when developing this library.**

This follows the polyrepo agent strategy documented in `bot_army_infra/CLAUDE.md`.

### When to Use Haiku Agents

- Exploring the decoder implementation and schema loading logic
- Reading test files to understand expected behavior
- Diagnostics: checking test failures, understanding error logs
- Code search: finding specific message envelope handling code
- Verification: running tests, checking backward compatibility

**Why**: Fast iteration loop, perfect for understanding existing code and validation.

### When to Use Sonnet Agents

- Implementing new decoder features or message types
- Designing changes to schema handling
- Backward compatibility validation
- Refactoring the NATS decoder for new requirements
- Complex changes affecting all downstream bots

**Why**: This is a foundation library — changes ripple to every bot. Deep reasoning ensures correctness.

### Example: Extend Message Envelope

```
User: "Add request_id field to message envelope"
  ↓
1. Haiku (Explore): Read envelope schema, current decoder implementation
  ↓
2. Sonnet (Plan): Design decoder changes, migration path for older messages
   Identify all places envelope is used, test strategy
  ↓
3. Sonnet (Implement): Update decoder, add migration logic, add tests
  ↓
4. Haiku (Verify): Run test suite, check backward compatibility
```
