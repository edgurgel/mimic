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
              # whether the suite-end soft_reset hook has been registered
              soft_reset_registered: false,
              lazy_allowances: %{}
  end

  @long_timeout Application.compile_env(:mimic, :server_timeout, 60_000)

  # Shared table holding owner allowances and the private/global mode flag.
  @table Mimic.Coordinator

  # Fast-path lookup to avoid a GenServer call when no lazy allowances exist for a module
  @lazy_modules_table :lazy_modules

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

  @spec allow(module, pid, pid) :: {:ok, module} | {:error, :global}
  def allow(module, owner_pid, allowed_pid) do
    GenServer.call(__MODULE__, {:allow, module, owner_pid, allowed_pid}, @long_timeout)
  end

  @spec allow_lazy(module, pid, (-> pid | [pid] | nil)) :: {:ok, module} | {:error, :global}
  def allow_lazy(module, owner_pid, fun) when is_function(fun, 0) do
    GenServer.call(__MODULE__, {:allow_lazy, module, owner_pid, fun}, @long_timeout)
  end

  @spec resolve_lazy(module, [pid]) :: {:ok, pid} | :none | {:error, {:invalid_lazy_result, term}}
  def resolve_lazy(module, caller_pids) do
    GenServer.call(__MODULE__, {:resolve_lazy, module, caller_pids}, @long_timeout)
  end

  @spec clear_global_owner(pid) :: :ok
  def clear_global_owner(pid) do
    GenServer.cast(__MODULE__, {:clear_global_owner, pid})
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
    :ets.new(@lazy_modules_table, [:named_table, :protected, :set, read_concurrency: true])

    :ets.insert(@table, {:mode, :private})
    {:ok, %State{}}
  end

  def handle_call({:ensure_copied, module}, _from, state) do
    case ensure_module_copied(module, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
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

  def handle_call({:allow_lazy, module, owner_pid, fun}, _from, state) do
    case :ets.lookup(@table, :mode) do
      [{:mode, :private}] ->
        Process.monitor(owner_pid)
        :ets.insert(@lazy_modules_table, {module, true})

        actual_owner =
          case :ets.lookup(@table, {owner_pid, module}) do
            [{{^owner_pid, ^module}, actual_owner_pid}] -> actual_owner_pid
            [] -> owner_pid
          end

        lazy_allowances =
          Map.update(state.lazy_allowances, {actual_owner, module}, [fun], &[fun | &1])

        {:reply, {:ok, module}, %{state | lazy_allowances: lazy_allowances}}

      [{:mode, :global, _global_pid}] ->
        {:reply, {:error, :global}, state}
    end
  end

  def handle_call({:resolve_lazy, module, caller_pids}, _from, state) do
    case find_lazy_owner(state.lazy_allowances, module, caller_pids) do
      {:ok, owner_pid} -> {:reply, {:ok, owner_pid}, state}
      {:error, _} = error -> {:reply, error, state}
      :none -> {:reply, :none, state}
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

    :ets.delete_all_objects(@lazy_modules_table)
    :ets.insert(@table, {:mode, :private})
    {:reply, :ok, %{state | lazy_allowances: %{}}}
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
      # Otherwise just store the module that will be copied
      # and ensure_module_copied/2 will copy it when
      # expect, stub, or reject is called
      state = %{
        state
        | modules_to_be_copied: MapSet.put(state.modules_to_be_copied, module),
          modules_opts: Map.put(state.modules_opts, module, opts)
      }

      state =
        if Cover.enabled_for?(module) do
          {:ok, state} = ensure_module_copied(module, state)
          state
        else
          state
        end

      {:reply, :ok, state}
    end
  end

  def handle_cast({:clear_global_owner, pid}, state) do
    case :ets.lookup(@table, :mode) do
      [{:mode, :global, ^pid}] -> :ets.insert(@table, {:mode, :private})
      _ -> :ok
    end

    {:noreply, state}
  end

  # Reset task has successfully finished
  def handle_info({ref, :ok}, state) do
    reset_tasks = Map.delete(state.reset_tasks, ref)

    {:noreply, %{state | reset_tasks: reset_tasks}}
  end

  # DOWN from a completed reset task or an owner pid monitored via allow_lazy/3
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, remove_lazy_allowances(pid, state)}
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

  defp remove_lazy_allowances(pid, state) do
    removed_modules =
      state.lazy_allowances
      |> Enum.filter(fn {{owner_pid, _module}, _funs} -> owner_pid == pid end)
      |> Enum.map(fn {{_owner_pid, module}, _funs} -> module end)

    lazy_allowances =
      state.lazy_allowances
      |> Enum.reject(fn {{owner_pid, _module}, _funs} -> owner_pid == pid end)
      |> Map.new()

    for module <- removed_modules do
      still_has_lazy? = Enum.any?(lazy_allowances, fn {{_owner_pid, m}, _funs} -> m == module end)
      if not still_has_lazy?, do: :ets.delete(@lazy_modules_table, module)
    end

    %{state | lazy_allowances: lazy_allowances}
  end

  defp find_lazy_owner(lazy_allowances, module, caller_pids) do
    Enum.find_value(lazy_allowances, :none, fn
      {{owner_pid, ^module}, funs} ->
        case any_pid_matches?(funs, caller_pids) do
          true -> {:ok, owner_pid}
          false -> nil
          {:error, _} = error -> error
        end

      _ ->
        nil
    end)
  end

  # Returns true, false, or {:error, _}
  defp any_pid_matches?(funs, caller_pids) do
    Enum.reduce_while(funs, false, fn fun, _acc ->
      case lazy_fun_result(fun) do
        {:error, _} = error -> {:halt, error}
        pids -> if Enum.any?(pids, &(&1 in caller_pids)), do: {:halt, true}, else: {:cont, false}
      end
    end)
  end

  defp lazy_fun_result(fun) do
    case fun.() do
      nil -> []
      pid when is_pid(pid) -> [pid]
      pids when is_list(pids) -> validate_pids(pids)
      other -> invalid_lazy_result(other)
    end
  end

  defp validate_pids(pids) do
    if Enum.all?(pids, &is_pid/1) do
      pids
    else
      invalid_lazy_result(pids)
    end
  end

  defp invalid_lazy_result(value), do: {:error, {:invalid_lazy_result, value}}
end
