defmodule Mimic.Server do
  @moduledoc false

  @long_timeout Application.compile_env(:mimic, :server_timeout, 60_000)
  @ownership_table __MODULE__
  @partition_supervisor Mimic.Server.PartitionSupervisor
  @supervisor Mimic.Server.Supervisor

  @spec child_spec(term) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_link(_opts) do
    partitions = Application.get_env(:mimic, :server_partitions, System.schedulers_online())

    children = [
      {Mimic.Server.Control, ownership_table: @ownership_table},
      {PartitionSupervisor,
       child_spec: Mimic.Server.Partition, name: @partition_supervisor, partitions: partitions}
    ]

    Supervisor.start_link(children, name: @supervisor, strategy: :rest_for_one)
  end

  @spec allow(module, pid, pid) :: {:ok, module} | {:error, :global}
  def allow(module, owner_pid, allowed_pid) do
    GenServer.call(partition(module), {:allow, module, owner_pid, allowed_pid})
  end

  @spec verify(pid) :: list({{module, atom, arity}, non_neg_integer, non_neg_integer})
  def verify(pid) do
    {:verify, pid}
    |> call_partitions(@long_timeout)
    |> List.flatten()
  end

  @spec verify_on_exit(pid) :: :ok
  def verify_on_exit(pid) do
    call_partitions({:verify_on_exit, pid}, @long_timeout)
    :ok
  end

  @spec stub(module, atom, arity, function) ::
          {:ok, module} | {:error, :not_global_owner} | {:error, {:module_not_copied, module}}
  def stub(module, fn_name, arity, func) do
    GenServer.call(
      partition(module),
      {:stub, module, fn_name, func, arity, self()},
      @long_timeout
    )
  end

  @spec stub(module) ::
          {:ok, module} | {:error, :not_global_owner} | {:error, {:module_not_copied, module}}
  def stub(module) do
    GenServer.call(partition(module), {:stub, module, self()}, @long_timeout)
  end

  @spec stub_with(module, module) ::
          {:ok, module} | {:error, :not_global_owner} | {:error, {:module_not_copied, module}}
  def stub_with(module, mocking_module) do
    GenServer.call(partition(module), {:stub_with, module, mocking_module, self()}, @long_timeout)
  end

  @spec expect(module, atom, arity, non_neg_integer, function) ::
          {:ok, module} | {:error, :not_global_owner} | {:error, {:module_not_copied, module}}
  def expect(module, fn_name, arity, num_calls, func) do
    GenServer.call(
      partition(module),
      {:expect, {module, fn_name, func, arity}, num_calls, self()},
      @long_timeout
    )
  end

  @spec set_global_mode(pid) :: :ok
  def set_global_mode(owner_pid) do
    :ets.insert(@ownership_table, {:mode, :global, owner_pid})
    :ok
  end

  @spec set_private_mode :: :ok
  def set_private_mode do
    :ets.insert(@ownership_table, {:mode, :private})
    :ok
  end

  @spec get_mode :: :private | :global
  def get_mode do
    mode_info() |> elem(0)
  end

  @spec exit(pid) :: :ok
  def exit(pid) do
    cast_partitions({:exit, pid})
    :ok
  end

  @spec reset(module) :: :ok
  def reset(module) do
    GenServer.call(partition(module), {:reset, module}, @long_timeout)
  end

  @spec soft_reset(module) :: :ok
  def soft_reset(_module) do
    set_private_mode()
    call_partitions(:soft_reset, @long_timeout)
    :ok
  end

  @spec mark_to_copy(module, keyword) :: :ok | {:error, {:module_already_copied, module}}
  def mark_to_copy(module, opts) do
    GenServer.call(partition(module), {:mark_to_copy, module, opts}, @long_timeout)
  end

  @spec marked_to_copy?(module) :: boolean
  def marked_to_copy?(module) do
    GenServer.call(partition(module), {:marked_to_copy?, module}, @long_timeout)
  end

  @spec get_calls(module, atom, arity) :: {:ok, list(list(term))} | {:error, :not_found}
  def get_calls(module, fn_name, arity) do
    caller_pids = [self() | Process.get(:"$callers", [])]

    GenServer.call(
      partition(module),
      {:get_calls, {module, fn_name, arity}, self(), caller_pids}
    )
  end

  def apply(module, fn_name, args) do
    arity = Enum.count(args)
    original_module = Mimic.Module.original(module)

    if function_exported?(original_module, fn_name, arity) do
      caller_pids = [self() | Process.get(:"$callers", [])]

      case allowed_pid(caller_pids, module) do
        {:ok, owner_pid} ->
          do_apply(owner_pid, module, fn_name, arity, args)

        _ ->
          apply_original(module, fn_name, args)
      end
    else
      raise Mimic.Error, module: module, fn_name: fn_name, arity: arity
    end
  end

  def ownership_table, do: @ownership_table

  def mode_info do
    case :ets.lookup(@ownership_table, :mode) do
      [{:mode, :global, global_pid}] -> {:global, global_pid}
      _ -> {:private, nil}
    end
  end

  def global_owner?(pid), do: mode_info() == {:global, pid}

  def insert_owner(module, pid, owner_pid) do
    :ets.insert(@ownership_table, {{module, pid}, owner_pid})
  end

  def insert_new_owner(module, pid, owner_pid) do
    :ets.insert_new(@ownership_table, {{module, pid}, owner_pid})
  end

  def lookup_owner(module, pid) do
    case :ets.lookup(@ownership_table, {module, pid}) do
      [{{^module, ^pid}, owner_pid}] -> {:ok, owner_pid}
      [] -> :error
    end
  end

  def clear_ownership(pid) do
    select = [{{{:_, pid}, :_}, [], [true]}, {{{:_, :_}, pid}, [], [true]}]
    :ets.select_delete(@ownership_table, select)
  end

  def allowed_pid(pids, module) do
    case mode_info() do
      {:private, _} ->
        Enum.find_value(pids, :none, fn pid ->
          case lookup_owner(module, pid) do
            {:ok, owner_pid} -> {:ok, owner_pid}
            :error -> false
          end
        end)

      {:global, global_pid} ->
        case lookup_owner(module, global_pid) do
          {:ok, owner_pid} -> {:ok, owner_pid}
          :error -> :none
        end
    end
  end

  defp do_apply(owner_pid, module, fn_name, arity, args) do
    case GenServer.call(
           partition(module),
           {:apply, owner_pid, module, fn_name, arity, args},
           :infinity
         ) do
      {:ok, func} ->
        Kernel.apply(func, args)

      :original ->
        apply_original(module, fn_name, args)

      {:unexpected, :fulfilled} ->
        mfa = Exception.format_mfa(module, fn_name, arity)

        raise Mimic.UnexpectedCallError,
              "#{mfa} called in process #{inspect(self())} but expectations are already fulfilled"

      {:unexpected, num_calls, num_applied_calls} ->
        mfa = Exception.format_mfa(module, fn_name, arity)

        raise Mimic.UnexpectedCallError,
              "expected #{mfa} to be called #{num_calls} time(s) " <>
                "but it has been called #{num_applied_calls} time(s) in process #{inspect(self())}"
    end
  end

  defp apply_original(module, fn_name, args),
    do: Kernel.apply(Mimic.Module.original(module), fn_name, args)

  defp partition(module), do: {:via, PartitionSupervisor, {@partition_supervisor, module}}

  defp call_partitions(message, timeout) do
    Enum.map(partition_pids(), &GenServer.call(&1, message, timeout))
  end

  defp cast_partitions(message) do
    Enum.each(partition_pids(), &GenServer.cast(&1, message))
  end

  defp partition_pids do
    @partition_supervisor
    |> Supervisor.which_children()
    |> Enum.flat_map(fn
      {_id, pid, _type, _modules} when is_pid(pid) -> [pid]
      _ -> []
    end)
  end
end
