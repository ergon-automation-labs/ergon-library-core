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

  ## Unified Skill Dispatch

  Both compiled skills and DB-driven skills share the same dispatch path:
  - `skill_index` maps `{trigger_pattern => {:compiled, module} | {:db, skill_definition}}`
  - `name_index` maps `{name_or_slug => {:compiled, module} | {:db, skill_definition}}`
  - When `db_skills: true`, DB skills are loaded on init and merged into both indexes
  - Cache invalidation triggers a reload of DB skill entries

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
      Synchronously run a skill by name (atom) or slug (string).
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

        compiled_index = build_skill_index(@skills)
        compiled_names = build_name_index(@skills)

        state = %{
          bot_id: @bot_id,
          personality: @personality.config(),
          context: %{},
          skill_index: compiled_index,
          name_index: compiled_names,
          started_at: started_at,
          tenant_id: @db_tenant_id,
          repo: @db_repo
        }

        unquote(
          if db_skills do
            quote do
              state = merge_db_skills(state)
            end
          end
        )

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
          for {trigger, _entry} <- state.skill_index do
            BotArmyCore.NATS.subscribe(trigger)
          end

          BotArmyCore.NATS.subscribe("context.current")
          BotArmyCore.NATS.subscribe("bot.army.#{@bot_id}.command.>")

          unquote(
            if db_skills do
              quote do
                BotArmyCore.NATS.subscribe("bot.army.skills.cache.invalidate")
              end
            end
          )

          :ok
        rescue
          e ->
            Logger.error("[#{@bot_id}] Subscription error", error: inspect(e))
            {:error, :subscription_failed}
        end
      end

      @impl true
      def handle_call({:run_skill, skill_name, input}, _from, state) do
        case Map.get(state.name_index, skill_name) do
          nil ->
            {:reply, {:error, {:skill_not_found, skill_name}}, state}

          {:compiled, skill} ->
            ctx = build_ctx(state)

            case skill.validate(input) do
              :ok ->
                case skill.execute(input, ctx) do
                  {:ok, result} ->
                    on_skill_success({:compiled, skill}, result, state)
                    {:reply, {:ok, result}, state}

                  {:error, reason} ->
                    on_skill_error({:compiled, skill}, reason, state)
                    {:reply, {:error, reason}, state}
                end

              {:error, reason} ->
                {:reply, {:error, {:validation_failed, reason}}, state}
            end

          {:db, skill_def} ->
            unquote(
              if db_skills do
                quote do
                  ctx = build_ctx(state)

                  case BotArmySkills.SkillRunner.execute(skill_def, input, ctx, repo: state.repo) do
                    {:ok, result} ->
                      on_skill_success({:db, skill_def}, result, state)
                      {:reply, {:ok, result}, state}

                    {:error, reason} ->
                      on_skill_error({:db, skill_def}, reason, state)
                      {:reply, {:error, reason}, state}
                  end
                end
              else
                quote do
                  {:reply, {:error, {:db_skills_not_enabled, skill_name}}, state}
                end
              end
            )
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
        BotArmyCore.NATS.publish("bot.army.health.#{@bot_id}", %{
          bot_id: @bot_id,
          status: :healthy,
          skills: length(@skills),
          db_skills:
            unquote(
              if db_skills, do: quote(do: map_size(state.name_index) - length(@skills)), else: 0
            ),
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
          matching = find_matching_skills(subject, state.skill_index)

          Enum.each(matching, fn entry ->
            Task.start(fn ->
              ctx = build_ctx(state)
              dispatch_skill(entry, payload, ctx, state)
            end)
          end)

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

      unquote(
        if db_skills do
          quote do
            @impl true
            def handle_info(
                  {:msg, %{topic: "bot.army.skills.cache.invalidate", body: body}},
                  state
                ) do
              case Jason.decode(body) do
                {:ok, %{"tenant_id" => tid}} when tid == state.tenant_id ->
                  Logger.info("[#{@bot_id}] DB skills cache invalidated, reloading")
                  {:noreply, merge_db_skills(state)}

                {:ok, %{"tenant_id" => _other}} ->
                  {:noreply, state}

                _ ->
                  # Unknown payload shape, reload anyway
                  Logger.info(
                    "[#{@bot_id}] DB skills cache invalidated (unknown tenant), reloading"
                  )

                  {:noreply, merge_db_skills(state)}
              end
            rescue
              _ ->
                {:noreply, state}
            end
          end
        end
      )

      def handle_info(msg, state) do
        Logger.debug("[#{@bot_id}] Ignoring unknown message", message: inspect(msg))
        {:noreply, state}
      end

      @doc false
      def on_skill_success(skill_entry, result, state) do
        skill_name = skill_name_from_entry(skill_entry)

        BotArmyCore.NATS.publish(
          "bot.army.#{state.bot_id}.event.skill_completed",
          %{
            "skill" => Atom.to_string(skill_name),
            "result" => result,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        )
      end

      defoverridable on_skill_success: 3

      @doc false
      def on_skill_error(skill_entry, reason, state) do
        skill_name = skill_name_from_entry(skill_entry)

        Logger.error("[#{state.bot_id}] Skill failed",
          skill: skill_name,
          reason: inspect(reason)
        )

        BotArmyCore.NATS.publish(
          "bot.army.#{state.bot_id}.event.skill_failed",
          %{
            "skill" => Atom.to_string(skill_name),
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
            {trigger, {:compiled, skill}}
          end)
        end)
      end

      defp build_name_index(skills) do
        Enum.into(skills, %{}, fn skill ->
          {skill.name(), {:compiled, skill}}
        end)
      end

      defp find_matching_skills(subject, skill_index) do
        skill_index
        |> Enum.filter(fn {pattern, _entry} ->
          BotArmyCore.NATS.subject_matches?(pattern, subject)
        end)
        |> Enum.map(fn {_pattern, entry} -> entry end)
        |> Enum.uniq()
      end

      defp dispatch_skill({:compiled, skill}, payload, ctx, state) do
        case skill.validate(payload) do
          :ok ->
            case skill.execute(payload, ctx) do
              {:ok, result} ->
                on_skill_success({:compiled, skill}, result, state)

              {:error, reason} ->
                on_skill_error({:compiled, skill}, reason, state)
            end

          {:error, reason} ->
            Logger.warning("[#{@bot_id}] Skill validation failed",
              skill: skill.name(),
              reason: reason
            )
        end
      end

      unquote(
        if db_skills do
          quote do
            defp dispatch_skill({:db, skill_def}, payload, ctx, state) do
              case BotArmySkills.SkillRunner.execute(skill_def, payload, ctx, repo: state.repo) do
                {:ok, result} ->
                  on_skill_success({:db, skill_def}, result, state)

                {:error, reason} ->
                  on_skill_error({:db, skill_def}, reason, state)
              end
            end

            defp merge_db_skills(state) do
              tenant_id = state.tenant_id || BotArmyRuntime.Tenant.default_tenant_id()
              repo = state.repo

              try do
                db_skills_list = BotArmySkills.SkillCache.list_skills(tenant_id, repo: repo)

                db_index =
                  Enum.flat_map(db_skills_list, fn skill_def ->
                    triggers = skill_def.triggers || []

                    Enum.map(triggers, fn trigger ->
                      {trigger, {:db, skill_def}}
                    end)
                  end)

                db_names =
                  Enum.reduce(db_skills_list, %{}, fn skill_def, acc ->
                    # Index by both atom name and string slug
                    acc
                    |> Map.put(skill_def.name, {:db, skill_def})
                    |> Map.put(skill_def.slug, {:db, skill_def})
                  end)

                # Remove old DB entries, keep compiled entries
                compiled_index =
                  Enum.filter(state.skill_index, fn
                    {_trigger, {:compiled, _}} -> true
                    _ -> false
                  end)

                compiled_names =
                  Enum.filter(state.name_index, fn
                    {_name, {:compiled, _}} -> true
                    _ -> false
                  end)
                  |> Enum.into(%{})

                %{
                  state
                  | skill_index: compiled_index ++ db_index,
                    name_index: Map.merge(compiled_names, db_names)
                }
              rescue
                e ->
                  Logger.warning("[#{@bot_id}] Failed to load DB skills",
                    error: inspect(e)
                  )

                  state
              end
            end
          end
        end
      )

      defp skill_name_from_entry({:compiled, skill}), do: skill.name()
      defp skill_name_from_entry({:db, skill_def}), do: skill_def.name

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
    end
  end
end
