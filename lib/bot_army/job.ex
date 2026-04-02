defmodule BotArmy.Job do
  @moduledoc """
  Behaviour for BotArmy jobs.

  Jobs are scheduled tasks that run periodically and invoke skills.

  ## Required Callbacks

  - `name/0` — Atom name for the job (e.g., `:daily_digest`)
  - `schedule/0` — Cron expression for when to run (e.g., `"0 8 * * *"` for 8am daily)
  - `skill/0` — Atom name of the skill to invoke
  - `build_input/1` — Build the input map for the skill given context

  ## Example

      defmodule MyBot.Jobs.DailyDigest do
        @behaviour BotArmy.Job

        def name, do: :daily_digest
        def schedule, do: "0 8 * * *"  # 8am every day
        def skill, do: :summarize

        def build_input(_ctx) do
          %{"text" => "Summary of events"}
        end
      end
  """

  @type context :: map()

  @callback name() :: atom()
  @callback schedule() :: String.t()
  @callback skill() :: atom()
  @callback build_input(context()) :: map()
end
