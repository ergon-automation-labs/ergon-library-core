# BotArmyCore

The shared Elixir library foundation for the Bot Army ecosystem.

BotArmyCore provides:
- NATS message envelope handling and decoding
- Integration with JSON Schema definitions (from `bot_army_schemas`)
- Standard error and acknowledgment shapes
- System health and alert definitions

## Installation

Add `bot_army_core` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:bot_army_core, git: "https://github.com/your-org/bot_army_core.git"}
  ]
end
```

Then run:
```bash
mix deps.get
```

## Usage

### NATS Message Decoding

```elixir
alias BotArmyCore.NATS.Decoder

# Decode a raw NATS message
{:ok, envelope} = Decoder.decode(raw_json_message)

# Load schema for validation
{:ok, schema} = Decoder.load_schema("envelope")
```

See `lib/bot_army_core/nats/decoder.ex` for detailed documentation.

## Schema Definitions

Core schemas are defined in the `bot_army_schemas` repository and deployed to:
```
/etc/bot_army/schemas/core/
```

Available schemas:
- `envelope.json` - Immutable message wrapper (event_id, event, schema_version, timestamp, etc.)
- `error.json` - Standard error response shape
- `system.health.json` - System heartbeat definition
- `system.alert.json` - System alert definition
- `triggered_by.json` - Valid audit trigger value enum

## Development

### Setup

```bash
mix deps.get
mix test
```

### Running Tests

```bash
mix test
```

### Code Quality

```bash
mix credo          # Linting
mix dialyzer       # Static analysis
mix excoveralls    # Code coverage
```

## Deployment

See `bot_army_infra` for deployment configuration.

When deploying changes:
1. Update schemas in `bot_army_schemas` first
2. Deploy updated `bot_army_core`
3. Deploy dependent bots

## Related Repositories

- `bot_army_schemas` - Core message contract definitions
- `bot_army_schemas_*` - Per-bot schema definitions
- `bot_army_infra` - Salt infrastructure and deployment
- Individual bots depend on this library

## License

TBD
