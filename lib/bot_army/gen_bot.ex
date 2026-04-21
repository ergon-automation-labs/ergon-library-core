defmodule BotArmy.GenBot do
  @moduledoc """
  Macro for creating a GenBot harness.

  The GenBot harness is a GenServer that:
  - Subscribes to skill trigger subjects via NATS
  - Routes incoming messages to matching skills
  - Runs skills asynchronously
  - Provides context injection (personality, current context, LLM proxy)
  - Publishes skill completion/error events
  - Maintains a heartbeat

  ## Usage

      defmodule MyBot do
        use BotArmy.GenBot,
          skills: [MyBot.Skills.Summarize, MyBot.Skills.Classify],
          jobs: [MyBot.Jobs.DailyDigest],
          personality: MyBot.Personality,
          bot_id: :my_bot
      end

  ## Configuration

  - `skills` — List of skill modules (must implement BotArmy.Skill)
  - `jobs` — List of job modules (must implement BotArmy.Job) - optional, defaults to []
  - `personality` — Personality module with config/0 - optional, defaults to BotArmy.DefaultPersonality
  - `bot_id` — Atom identifier for the bot
  - `db_skills` — Enable DB-driven markdown skills (requires bot_army_skills dependency) - optional, defaults to false
  - `tenant_id` — Tenant ID for DB-driven skills - optional, defaults to nil (uses default tenant)
  - `repo` — Ecto Repo module for DB-driven skills - optional, defaults to BotArmyRuntime.Ecto.Repo

  ## Context Provided to Skills

  ```elixir
  %{
    bot_id: :atom,
    personality: map(),         # From personality.config()
    context: map(),             # From context.current NATS subject
    llm: BotArmy.LLMProxy       # For calling LLM
  }
  ```

  ## Overridable Hooks

  - `on_skill_success/3` — Called when a skill succeeds
  - `on_skill_error/3` — Called when a skill fails

  ## Example with Hooks

      defmodule MyBot do
        use BotArmy.GenBot,
          skills: [MyBot.Skills.Summarize],
          bot_id: :my_bot

        def on_skill_success(skill, result, state) do
          # Custom success handling
          super(skill, result, state)
        end
      end
  """

  require Logger

  defmacro __using__(opts) do
    skills = Keyword.fetch!(opts, :skills)
    jobs = Keyword.get(opts, :jobs, [])
    personality = Keyword.get(opts, :personality, BotArmy.DefaultPersonality)
    bot_id = Keyword.fetch!(opts, :bot_id)
    db_skills = Keyword.get(opts, :db_skills, false)
    tenant_id = Keyword.get(opts, :tenant_id, nil)
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    quote do
      use GenServer

      @skills unquote(skills)
      @jobs unquote(jobs)
      @personality unquote(personality)
      @bot_id unquote(bot_id)
      @db_skills unquote(db_skills)
      @db_tenant_id unquote(tenant_id)
      @db_repo unquote(repo)

      require Logger

      @doc """
      Start the GenBot.
      """
      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @doc """
      Synchronously run a skill by name.
      """
      def run_skill(skill_name, input) do
        GenServer.call(__MODULE__, {:run_skill, skill_name, input}, 10_000)
      end

      @doc """
      Get the list of registered skills.
      """
      def skills, do: @skills

      @doc """
      Get the list of registered jobs.
      """
      def jobs, do: @jobs

      @doc """
      Get the bot's ID.
      """
      def bot_id, do: @bot_id

      @impl true
      def init(opts) do
        Logger.info("[#{@bot_id}] Starting GenBot",
          skills: Enum.map(@skills, & &1.name()),
          bot_id: @bot_id
        )

        started_at = DateTime.utc_now()

        state = %{
          bot_id: @bot_id,
          personality: @personality.config(),
          context: %{},
          skill_index: build_skill_index(@skills),
          name_index: build_name_index(@skills),
          started_at: started_at,
          tenant_id: @db_tenant_id,
          repo: @db_repo
        }

        # Try to subscribe to all subjects, with retry on failure
        case subscribe_to_subjects(state) do
          :ok ->
            # Schedule first heartbeat in 30 seconds
            Process.send_after(self(), :heartbeat, 30_000)
            {:ok, state}

          {:error, reason} ->
            Logger.error("[#{@bot_id}] Failed to subscribe to subjects",
              reason: inspect(reason)
            )

            # Retry subscription after 2 seconds
            Process.send_after(self(), :subscribe_retry, 2_000)
            {:ok, state}
        end
      end

      defp subscribe_to_subjects(state) do
        try do
          # Subscribe to all skill triggers (skill_index is already {trigger -> skill} map)
          for {trigger, _skill} <- state.skill_index do
            BotArmyCore.NATS.subscribe(trigger)
          end

          # Subscribe to context updates
          BotArmyCore.NATS.subscribe("context.current")

          # Subscribe to direct commands for this bot
          BotArmyCore.NATS.subscribe("bot.army.#{@bot_id}.command.>")

          :ok
        rescue
          e ->
            Logger.error("[#{@bot_id}] Subscription error", error: inspect(e))
            {:error, :subscription_failed}
        end
      end

      @impl true
      def handle_call({:run_skill, skill_name, input}, _from, state) do
        skill = state.name_index[skill_name]

        if skill do
          ctx = build_ctx(state)

          case skill.validate(input) do
            :ok ->
              case skill.execute(input, ctx) do
                {:ok, result} ->
                  on_skill_success(skill, result, state)
                  {:reply, {:ok, result}, state}

                {:error, reason} ->
                  on_skill_error(skill, reason, state)
                  {:reply, {:error, reason}, state}
              end

            {:error, reason} ->
              {:reply, {:error, {:validation_failed, reason}}, state}
          end
        else
          {:reply, {:error, {:skill_not_found, skill_name}}, state}
        end
      end

      @impl true
      def handle_info(:subscribe_retry, state) do
        Logger.debug("[#{@bot_id}] Retrying NATS subscriptions")

        case subscribe_to_subjects(state) do
          :ok ->
            Process.send_after(self(), :heartbeat, 30_000)
            {:noreply, state}

          {:error, _reason} ->
            Process.send_after(self(), :subscribe_retry, 2_000)
            {:noreply, state}
        end
      end

      @impl true
      def handle_info(:heartbeat, state) do
        # Current heartbeat - expanded with full state
        BotArmyCore.NATS.publish("bot.army.health.#{@bot_id}", %{
          bot_id: @bot_id,
          status: :healthy,
          skills: length(@skills),
          uptime_sec:
            DateTime.diff(DateTime.utc_now(), Map.get(state, :started_at, DateTime.utc_now())),
          context: state.context,
          personality: state.personality
        })

        Process.send_after(self(), :heartbeat, 30_000)
        {:noreply, state}
      end

      @impl true
      def handle_info({:msg, %{topic: "context.current", body: body}}, state) do
        try do
          context = Jason.decode!(body)
          {:noreply, %{state | context: context}}
        rescue
          e ->
            Logger.error("[#{@bot_id}] Failed to decode context", error: inspect(e))
            {:noreply, state}
        end
      end

      @impl true
      def handle_info({:msg, %{topic: subject, body: body}}, state) do
        try do
          payload = Jason.decode!(body)
          matching_skills = find_matching_skills(subject, state.skill_index)

          Enum.each(matching_skills, fn skill ->
            Task.start(fn ->
              ctx = build_ctx(state)

              case skill.validate(payload) do
                :ok ->
                  case skill.execute(payload, ctx) do
                    {:ok, result} ->
                      on_skill_success(skill, result, state)

                    {:error, reason} ->
                      on_skill_error(skill, reason, state)
                  end

                {:error, reason} ->
                  Logger.warning("[#{@bot_id}] Skill validation failed",
                    skill: skill.name(),
                    reason: reason
                  )
              end
            end)
          end)

          # Dispatch to DB-driven skills if enabled
          if @db_skills do
            dispatch_db_skills(subject, payload, state)
          end

          {:noreply, state}
        rescue
          e ->
            Logger.error("[#{@bot_id}] Failed to handle NATS message",
              subject: subject,
              error: inspect(e)
            )

            {:noreply, state}
        end
      end

      def handle_info(msg, state) do
        Logger.debug("[#{@bot_id}] Ignoring unknown message", message: inspect(msg))
        {:noreply, state}
      end

      @doc false
      def on_skill_success(skill, result, state) do
        BotArmyCore.NATS.publish(
          "bot.army.#{state.bot_id}.event.skill_completed",
          %{
            "skill" => Atom.to_string(skill.name()),
            "result" => result,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        )
      end

      defoverridable on_skill_success: 3

      @doc false
      def on_skill_error(skill, reason, state) do
        Logger.error("[#{state.bot_id}] Skill failed",
          skill: skill.name(),
          reason: inspect(reason)
        )

        BotArmyCore.NATS.publish(
          "bot.army.#{state.bot_id}.event.skill_failed",
          %{
            "skill" => Atom.to_string(skill.name()),
            "reason" => inspect(reason),
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        )
      end

      defoverridable on_skill_error: 3

      # Private helpers

      defp build_skill_index(skills) do
        Enum.flat_map(skills, fn skill ->
          Enum.map(skill.nats_triggers(), fn trigger ->
            {trigger, skill}
          end)
        end)
      end

      defp build_name_index(skills) do
        Enum.into(skills, %{}, fn skill ->
          {skill.name(), skill}
        end)
      end

      defp find_matching_skills(subject, skill_index) do
        skill_index
        |> Enum.filter(fn {pattern, _skill} ->
          BotArmyCore.NATS.subject_matches?(pattern, subject)
        end)
        |> Enum.map(fn {_pattern, skill} -> skill end)
        |> Enum.uniq()
      end

      defp build_ctx(state) do
        %{
          bot_id: state.bot_id,
          personality: state.personality,
          context: state.context,
          llm: BotArmy.LLMProxy,
          embeddings: BotArmy.EmbeddingsProxy,
          tenant_id: state.tenant_id,
          repo: state.repo
        }
      end

      if @db_skills do
        defp dispatch_db_skills(subject, payload, state) do
          tenant_id = state.tenant_id || BotArmyRuntime.Tenant.default_tenant_id()
          repo = state.repo

          try do
            db_skills = BotArmySkills.SkillCache.list_skills(tenant_id, repo: repo)

            matching =
              Enum.filter(db_skills, fn skill ->
                Enum.any?(skill.triggers || [], fn trigger ->
                  BotArmyCore.NATS.subject_matches?(trigger, subject)
                end)
              end)

            Enum.each(matching, fn skill ->
              Task.start(fn ->
                ctx = build_ctx(state)
                BotArmySkills.SkillRunner.execute(skill, payload, ctx, repo: repo)
              end)
            end)
          rescue
            e ->
              Logger.warning("[#{@bot_id}] DB skill dispatch failed",
                error: inspect(e)
              )
          end
        end
      end
    end
  end
end
