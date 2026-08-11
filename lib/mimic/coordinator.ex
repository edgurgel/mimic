defmodule Mimic.Coordinator do
  use GenServer
  alias Mimic.Cover
  @moduledoc false

  # Owns everything global: the shared ETS table (owner allowances + mode flag), the
  # private/global mode switches, and the module copy/reset lifecycle. The
  # per-call dispatch path never goes through this process.

  defmodule State do
    @moduledoc false
    defstruct modules_beam: %{},
              modules_to_be_copied: MapSet.new(),
              modules_opts: %{},
              reset_tasks: %{},
              # ref => module for copies currently running in a Task
              copy_tasks: %{},
              # module => [GenServer from] waiting on that module's in-flight copy
              copy_waiters: %{},
              # whether the suite-end soft_reset hook has been registered
              soft_reset_registered: false
  end

  @long_timeout Application.compile_env(:mimic, :server_timeout, 60_000)

  # Shared table holding owner allowances and the private/global mode flag.
  @table Mimic.Coordinator

  @spec ensure_copied(module) :: :ok | {:error, {:module_not_copied, module}}
  def ensure_copied(module) do
    if Mimic.Module.copied?(module) do
      :ok
    else
      GenServer.call(__MODULE__, {:ensure_copied, module}, @long_timeout)
    end
  end

  @spec set_global_mode(pid) :: :ok
  def set_global_mode(owner_pid) do
    GenServer.call(__MODULE__, {:set_global_mode, owner_pid}, @long_timeout)
  end

  @spec set_private_mode :: :ok
  def set_private_mode do
    GenServer.call(__MODULE__, :set_private_mode, @long_timeout)
  end

  @spec get_mode :: :private | :global
  def get_mode do
    case :ets.lookup(@table, :mode) do
      [{:mode, :private}] -> :private
      [{:mode, :global, _owner_pid}] -> :global
    end
  end

  @spec mark_to_copy(module, keyword) :: :ok | {:error, {:module_already_copied, module}}
  def mark_to_copy(module, opts) do
    GenServer.call(__MODULE__, {:mark_to_copy, module, opts}, @long_timeout)
  end

  @spec marked_to_copy?(module) :: boolean
  def marked_to_copy?(module) do
    GenServer.call(__MODULE__, {:marked_to_copy?, module}, @long_timeout)
  end

  @spec reset(module) :: :ok
  def reset(module) do
    GenServer.call(__MODULE__, {:reset, module}, @long_timeout)
  end

  @spec soft_reset() :: :ok
  def soft_reset do
    GenServer.call(__MODULE__, :soft_reset, @long_timeout)
  end

  # Registers the single suite-end `soft_reset` hook, idempotently. `Mimic.copy/2`
  # is called once per copied module, but soft_reset wipes all partitions globally,
  # so we only ever need one after_suite callback regardless of module count.
  @spec register_soft_reset() :: :ok
  def register_soft_reset do
    GenServer.call(__MODULE__, :register_soft_reset, @long_timeout)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    :ets.insert(@table, {:mode, :private})
    {:ok, %State{}}
  end

  def handle_call({:ensure_copied, module}, from, state) do
    cond do
      Mimic.Module.copied?(module) ->
        {:reply, :ok, state}

      Map.has_key?(state.copy_waiters, module) ->
        # A copy for this module is already running — ride along and get replied
        # when it lands. One copy, many waiters.
        waiters = Map.update!(state.copy_waiters, module, &[from | &1])
        {:noreply, %{state | copy_waiters: waiters}}

      MapSet.member?(state.modules_to_be_copied, module) ->
        # Offload the recompile to a Task so the Coordinator keeps serving other
        # messages; `from` is answered via GenServer.reply when the Task finishes.
        {:noreply, start_copy(module, from, state)}

      true ->
        {:reply, {:error, {:module_not_copied, module}}, state}
    end
  end

  def handle_call({:set_global_mode, owner_pid}, _from, state) do
    :ets.insert(@table, {:mode, :global, owner_pid})
    {:reply, :ok, state}
  end

  def handle_call(:set_private_mode, _from, state) do
    :ets.insert(@table, {:mode, :private})
    {:reply, :ok, state}
  end

  def handle_call(:soft_reset, _from, state) do
    server_partitions()
    |> Task.async_stream(
      fn pid -> GenServer.call(pid, :soft_reset, @long_timeout) end,
      ordered: false,
      timeout: @long_timeout
    )
    |> Stream.run()

    :ets.insert(@table, {:mode, :private})
    {:reply, :ok, state}
  end

  def handle_call(:register_soft_reset, _from, state) do
    unless state.soft_reset_registered do
      ExUnit.after_suite(fn _ -> soft_reset() end)
    end

    {:reply, :ok, %{state | soft_reset_registered: true}}
  end

  def handle_call({:reset, module}, _from, state) do
    state = %{state | modules_to_be_copied: MapSet.delete(state.modules_to_be_copied, module)}

    tasks =
      if Mimic.Module.copied?(module) do
        task = Task.async(fn -> do_reset(module, state) end)

        Map.put(state.reset_tasks, task.ref, task)
      else
        state.reset_tasks
      end

    # Clear the beam modules after starting the tasks (they read the state)
    # This is important for umbrella apps since they'll run app after app
    # and the modules that need to be covered will change between apps
    state = %{state | modules_beam: Map.delete(state.modules_beam, module)}

    # All modules have been reset. We should await all tasks now
    if state.modules_to_be_copied == MapSet.new() do
      tasks
      |> Map.values()
      |> Task.await_many(@long_timeout)

      {:reply, :ok, %{state | reset_tasks: %{}}}
    else
      {:reply, :ok, %{state | reset_tasks: tasks}}
    end
  end

  def handle_call({:marked_to_copy?, module}, _from, state) do
    {:reply, marked_to_copy?(module, state), state}
  end

  def handle_call({:mark_to_copy, module, opts}, _from, state) do
    if marked_to_copy?(module, state) do
      {:reply, {:error, {:module_already_copied, module}}, state}
    else
      # If cover is enabled call ensure_module_copied now
      # Otherwise just store that the module that will be copied
      # and ensure_module_copied/2 will copy it when
      # expect, stub, reject is called
      state = %{
        state
        | modules_to_be_copied: MapSet.put(state.modules_to_be_copied, module),
          modules_opts: Map.put(state.modules_opts, module, opts)
      }

      state =
        if Cover.enabled_for?(module) do
          copy_inline(module, state)
        else
          state
        end

      {:reply, :ok, state}
    end
  end

  # Copy task finished. `result` is Mimic.Module.replace!/2's return: `:ok` or
  # `{beam_file, coverdata_path}`. Guarded so reset-task `:ok` messages fall
  # through to the clause below.
  def handle_info({ref, result}, state) when is_map_key(state.copy_tasks, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_copy(ref, {:ok, result}, state)}
  end

  # Copy task crashed before returning — surface the failure to its waiters
  # rather than leaving them blocked until their call times out.
  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.copy_tasks, ref) do
    {:noreply, finish_copy(ref, {:crash, reason}, state)}
  end

  # Reset task has successfully finished
  def handle_info({ref, :ok}, state) do
    reset_tasks = Map.delete(state.reset_tasks, ref)

    {:noreply, %{state | reset_tasks: reset_tasks}}
  end

  # DOWN from a completed reset task
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.puts("handle_info with #{inspect(msg)} not handled")
    {:noreply, state}
  end

  defp server_partitions do
    Mimic.Server.Partitions
    |> PartitionSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
  end

  defp marked_to_copy?(module, state) do
    MapSet.member?(state.modules_to_be_copied, module)
  end

  defp do_reset(module, state) do
    case state.modules_beam[module] do
      {beam, coverdata} -> Cover.clear_module_and_import_coverdata!(module, beam, coverdata)
      _ -> Mimic.Module.clear!(module)
    end
  end

  # Spawn an async copy for `module`, registering `from` as its first waiter.
  # The Task runs the recompile off the Coordinator's main loop; its result comes
  # back as a message handled by handle_info/2.
  defp start_copy(module, from, state) do
    opts = Map.get(state.modules_opts, module, [])

    # 0 -> 1: enable ignore_module_conflict for as long as any copy is in flight,
    # so every concurrent copy's `create_mock` redefinition compiles cleanly.
    if map_size(state.copy_tasks) == 0 do
      Code.compiler_options(ignore_module_conflict: true)
    end

    task =
      Task.Supervisor.async_nolink(Mimic.TaskSupervisor, fn ->
        Mimic.Module.replace!(module, opts)
      end)

    %{
      state
      | copy_tasks: Map.put(state.copy_tasks, task.ref, module),
        copy_waiters: Map.put(state.copy_waiters, module, [from])
    }
  end

  # A copy task settled (success or crash): update state, reply every waiter, and
  # drop the conflict flag once no copies remain in flight.
  defp finish_copy(ref, outcome, state) do
    {module, copy_tasks} = Map.pop(state.copy_tasks, ref)
    {waiters, copy_waiters} = Map.pop(state.copy_waiters, module, [])

    {reply, modules_beam} =
      case outcome do
        {:ok, {beam_file, coverdata_path}} ->
          {:ok, Map.put(state.modules_beam, module, {beam_file, coverdata_path})}

        {:ok, :ok} ->
          {:ok, state.modules_beam}

        {:crash, reason} ->
          {{:error, {:copy_failed, module, reason}}, state.modules_beam}
      end

    Enum.each(waiters, &GenServer.reply(&1, reply))

    # 1 -> 0: no copies left, restore the compiler default.
    if map_size(copy_tasks) == 0 do
      Code.compiler_options(ignore_module_conflict: false)
    end

    %{state | copy_tasks: copy_tasks, copy_waiters: copy_waiters, modules_beam: modules_beam}
  end

  # Synchronous copy used by the cover-eager mark_to_copy path. Holds the conflict
  # flag on for the duration, then restores it to whatever in-flight async copies
  # still require (never clobbers a concurrent copy's flag).
  defp copy_inline(module, state) do
    Code.compiler_options(ignore_module_conflict: true)

    try do
      {:ok, new_state} = ensure_module_copied(module, state)
      new_state
    after
      Code.compiler_options(ignore_module_conflict: map_size(state.copy_tasks) > 0)
    end
  end

  defp ensure_module_copied(module, state) do
    cond do
      Mimic.Module.copied?(module) ->
        {:ok, state}

      MapSet.member?(state.modules_to_be_copied, module) ->
        case Mimic.Module.replace!(module, state.modules_opts[module]) do
          {beam_file, coverdata_path} ->
            modules_beam = Map.put(state.modules_beam, module, {beam_file, coverdata_path})
            {:ok, %{state | modules_beam: modules_beam}}

          :ok ->
            {:ok, state}
        end

      true ->
        {:error, {:module_not_copied, module}}
    end
  end
end
