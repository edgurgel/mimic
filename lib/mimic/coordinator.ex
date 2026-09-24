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
              # module => %{ref: task_ref, waiting: [from]} for copies in flight
              modules_copying: %{},
              # task_ref => module, reverse index of modules_copying
              copy_tasks: %{},
              # value of `ignore_module_conflict` to restore once no copy is in flight
              saved_ignore_module_conflict: nil,
              modules_opts: %{},
              reset_tasks: %{},
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
      case GenServer.call(__MODULE__, {:ensure_copied, module}, @long_timeout) do
        # The copy task crashed. Surface it the same way a crash inside the
        # Coordinator used to: as an exit in the caller.
        {:exit, reason} -> exit({:module_copy_failed, module, reason})
        result -> result
      end
    end
  end

  @spec set_global_mode(pid) :: :ok
  def set_global_mode(owner_pid) do
    GenServer.call(__MODULE__, {:set_global_mode, owner_pid}, @long_timeout)
  end

  @spec allow(module, pid, pid) :: {:ok, module} | {:error, :global}
  def allow(module, owner_pid, allowed_pid) do
    GenServer.call(__MODULE__, {:allow, module, owner_pid, allowed_pid}, @long_timeout)
  end

  @spec release_global_owner(pid) :: :ok
  def release_global_owner(owner) do
    :ets.select_replace(@table, [{{:mode, :global, owner}, [], [{:const, {:mode, :private}}]}])
    :ok
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
    respond_ensure_module_copied(module, from, state)
  end

  def handle_call({:set_global_mode, owner_pid}, _from, state) do
    :ets.insert(@table, {:mode, :global, owner_pid})
    {:reply, :ok, state}
  end

  def handle_call(:set_private_mode, _from, state) do
    :ets.insert(@table, {:mode, :private})
    {:reply, :ok, state}
  end

  def handle_call({:allow, module, owner_pid, allowed_pid}, _from, state) do
    case :ets.lookup(@table, :mode) do
      [{:mode, :private}] ->
        case :ets.lookup(@table, {owner_pid, module}) do
          [{{^owner_pid, ^module}, actual_owner_pid}] ->
            :ets.insert(@table, {{allowed_pid, module}, actual_owner_pid})

          [] ->
            :ets.insert(@table, {{allowed_pid, module}, owner_pid})
        end

        {:reply, {:ok, module}, state}

      [{:mode, :global, _global_pid}] ->
        {:reply, {:error, :global}, state}
    end
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

    # A copy may still be in flight if the process that requested it died while
    # waiting (e.g. a test timeout). Wait for it so the reset below sees the copy.
    state = await_copy(module, state)

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

  def handle_call({:mark_to_copy, module, opts}, from, state) do
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

      if Cover.enabled_for?(module) do
        respond_ensure_module_copied(module, from, state)
      else
        {:reply, :ok, state}
      end
    end
  end

  # Reset task has successfully finished
  def handle_info({ref, :ok}, state) do
    reset_tasks = Map.delete(state.reset_tasks, ref)

    {:noreply, %{state | reset_tasks: reset_tasks}}
  end

  # Copy task finished
  def handle_info({ref, {:copied, data}}, state) when is_map_key(state.copy_tasks, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_copy(ref, {:ok, data}, state)}
  end

  # Copy task crashed (async_nolink, so we get the DOWN instead of dying with it)
  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.copy_tasks, ref) do
    {:noreply, finish_copy(ref, {:error, reason}, state)}
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

  defp respond_ensure_module_copied(module, from, state) do
    cond do
      Map.has_key?(state.modules_copying, module) ->
        {:noreply, add_waiter(module, from, state)}

      Mimic.Module.copied?(module) ->
        {:reply, :ok, state}

      MapSet.member?(state.modules_to_be_copied, module) ->
        {:noreply, start_copy(module, from, state)}

      true ->
        {:reply, {:error, {:module_not_copied, module}}, state}
    end
  end

  defp add_waiter(module, from, state) do
    modules_copying =
      Map.update!(state.modules_copying, module, fn copy ->
        %{copy | waiting: [from | copy.waiting]}
      end)

    %{state | modules_copying: modules_copying}
  end

  # Copying is slow (it recompiles the original module) so it runs in a task and
  # the caller is parked until it finishes. That keeps the Coordinator responsive
  # for unrelated modules and lets copies of different modules overlap.
  defp start_copy(module, from, state) do
    opts = state.modules_opts[module]

    # Global, non-idempotent-under-concurrency setup that used to be implicitly
    # serialised by running the copy inside this process. Do it here, once.
    state = ensure_ignore_module_conflict(state)
    if Cover.enabled_for?(module), do: Cover.export_private_functions()

    task =
      Task.Supervisor.async_nolink(Mimic.TaskSupervisor, fn ->
        {:copied, Mimic.Module.replace!(module, opts)}
      end)

    %{
      state
      | modules_copying:
          Map.put(state.modules_copying, module, %{ref: task.ref, waiting: [from]}),
        copy_tasks: Map.put(state.copy_tasks, task.ref, module)
    }
  end

  defp finish_copy(ref, result, state) do
    {module, copy_tasks} = Map.pop!(state.copy_tasks, ref)
    {%{waiting: waiting}, modules_copying} = Map.pop!(state.modules_copying, module)

    {reply, modules_beam} =
      case result do
        {:ok, {beam_file, coverdata_path}} ->
          {:ok, Map.put(state.modules_beam, module, {beam_file, coverdata_path})}

        {:ok, :ok} ->
          {:ok, state.modules_beam}

        {:error, reason} ->
          {{:exit, reason}, state.modules_beam}
      end

    Enum.each(waiting, &GenServer.reply(&1, reply))

    state = %{
      state
      | modules_beam: modules_beam,
        modules_copying: modules_copying,
        copy_tasks: copy_tasks
    }

    restore_ignore_module_conflict(state)
  end

  # Blocks until an in-flight copy of `module` (if any) is done and applied to the state.
  defp await_copy(module, state) do
    case state.modules_copying do
      %{^module => %{ref: ref}} ->
        receive do
          {^ref, {:copied, data}} ->
            Process.demonitor(ref, [:flush])
            finish_copy(ref, {:ok, data}, state)

          {:DOWN, ^ref, :process, _pid, reason} ->
            finish_copy(ref, {:error, reason}, state)
        after
          @long_timeout -> exit({:module_copy_timeout, module})
        end

      _ ->
        state
    end
  end

  # `ignore_module_conflict` is a VM-global compiler option. Copies now overlap, so
  # instead of toggling it around each copy (racy), set it while any copy is in
  # flight and put the previous value back once the last one finishes.
  defp ensure_ignore_module_conflict(%{copy_tasks: tasks} = state) when map_size(tasks) == 0 do
    previous = Map.get(Code.compiler_options(), :ignore_module_conflict, false)
    Code.compiler_options(ignore_module_conflict: true)
    %{state | saved_ignore_module_conflict: previous}
  end

  defp ensure_ignore_module_conflict(state), do: state

  defp restore_ignore_module_conflict(%{copy_tasks: tasks} = state) when map_size(tasks) == 0 do
    Code.compiler_options(ignore_module_conflict: state.saved_ignore_module_conflict)
    %{state | saved_ignore_module_conflict: nil}
  end

  defp restore_ignore_module_conflict(state), do: state
end
