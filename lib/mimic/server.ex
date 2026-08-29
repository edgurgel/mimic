defmodule Mimic.Server do
  use GenServer
  alias Mimic.Coordinator
  @moduledoc false

  # State is partitioned by owner pid across one server per scheduler (see
  # Mimic.Application). Stubs, expectations, call history, monitors for each owner
  # lives on the shard `:erlang.phash2(owner)` maps to, so per-owner ordering is
  # preserved while different owners no longer serialize through a single process.

  defmodule State do
    @moduledoc false
    defstruct verify_on_exit: MapSet.new(),
              stubs: %{},
              expectations: %{},
              call_history: %{}
  end

  defmodule Expectation do
    @moduledoc false
    defstruct func: nil, num_applied_calls: 0, num_calls: nil
  end

  @long_timeout Application.compile_env(:mimic, :server_timeout, 60_000)

  # Shared allowances/mode table owned by Mimic.Coordinator
  @table Mimic.Coordinator

  # Owned by Mimic.Coordinator, but read directly here
  @lazy_modules_table :lazy_modules

  defp shard(pid), do: {:via, PartitionSupervisor, {Mimic.Server.Partitions, pid}}

  @spec verify(pid) :: [{{module, atom, non_neg_integer}, non_neg_integer, non_neg_integer}]
  def verify(pid) do
    GenServer.call(shard(pid), {:verify, pid}, @long_timeout)
  end

  @spec verify_on_exit(pid) :: :ok
  def verify_on_exit(pid) do
    GenServer.call(shard(pid), {:verify_on_exit, pid}, @long_timeout)
  end

  @spec stub(module, atom, arity, function) ::
          {:ok, module} | {:error, :not_global_owner} | {:error, {:module_not_copied, module}}
  def stub(module, fn_name, arity, func) do
    with :ok <- Coordinator.ensure_copied(module) do
      GenServer.call(shard(self()), {:stub, module, fn_name, func, arity, self()}, @long_timeout)
    end
  end

  @spec stub(module) ::
          {:ok, module} | {:error, :not_global_owner} | {:error, {:module_not_copied, module}}
  def stub(module) do
    with :ok <- Coordinator.ensure_copied(module) do
      GenServer.call(shard(self()), {:stub, module, self()}, @long_timeout)
    end
  end

  @spec stub_with(module, module) ::
          {:ok, module} | {:error, :not_global_owner} | {:error, {:module_not_copied, module}}
  def stub_with(module, mocking_module) do
    with :ok <- Coordinator.ensure_copied(module) do
      GenServer.call(shard(self()), {:stub_with, module, mocking_module, self()}, @long_timeout)
    end
  end

  @spec expect(module, atom, arity, non_neg_integer, function) ::
          {:ok, module} | {:error, :not_global_owner} | {:error, {:module_not_copied, module}}
  def expect(module, fn_name, arity, num_calls, func) do
    with :ok <- Coordinator.ensure_copied(module) do
      GenServer.call(
        shard(self()),
        {:expect, {module, fn_name, func, arity}, num_calls, self()},
        @long_timeout
      )
    end
  end

  @spec exit(pid) :: :ok
  def exit(pid) do
    GenServer.cast(shard(pid), {:exit, pid})
  end

  @spec get_calls(module, atom, arity) ::
          {:ok, list(list(term))} | {:error, {:module_not_copied, module}}
  def get_calls(module, fn_name, arity) do
    with :ok <- Coordinator.ensure_copied(module) do
      caller_pids = [self() | Process.get(:"$callers", [])]

      owner_pid =
        case allowed_pid(caller_pids, module) do
          {:ok, pid} -> pid
          :none -> self()
        end

      GenServer.call(shard(owner_pid), {:get_calls, {module, fn_name, arity}, owner_pid})
    end
  end

  def apply(module, fn_name, args) do
    arity = Enum.count(args)
    original_module = Mimic.Module.original(module)

    if function_exported?(original_module, fn_name, arity) do
      caller_pids = [self() | Process.get(:"$callers", [])]

      with :none <- allowed_pid(caller_pids, module),
           :none <- resolve_lazy_allowance(caller_pids, module) do
        apply_original(module, fn_name, args)
      else
        {:ok, owner_pid} -> do_apply(owner_pid, module, fn_name, arity, args)
      end
    else
      raise Mimic.Error, module: module, fn_name: fn_name, arity: arity
    end
  end

  defp resolve_lazy_allowance(caller_pids, module) do
    @lazy_modules_table
    |> :ets.lookup(module)
    |> Enum.find_value(:none, fn {_module, owner_pid, fun} ->
      if lazy_fun_matches?(fun, caller_pids), do: {:ok, owner_pid}
    end)
  end

  defp lazy_fun_matches?(fun, caller_pids) do
    fun
    |> evaluate_lazy_fun()
    |> Enum.any?(&(&1 in caller_pids))
  end

  defp evaluate_lazy_fun(fun) do
    raw_result = fun.()

    pids =
      raw_result
      |> List.wrap()
      |> Enum.reject(&is_nil/1)

    if Enum.all?(pids, &is_pid/1) do
      pids
    else
      raise ArgumentError,
            "lazy allowance callback passed to allow/3 must return a pid or nil (or a list of those), got: #{inspect(raw_result)}"
    end
  end

  defp do_apply(owner_pid, module, fn_name, arity, args) do
    case GenServer.call(
           shard(owner_pid),
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

  defp allowed_pid(pids, module) do
    case :ets.lookup(@table, :mode) do
      [{:mode, :private}] ->
        find_owner(pids, module)

      [{:mode, :global, global_pid}] ->
        case find_owner([global_pid], module) do
          {:ok, _owner_pid} -> {:ok, global_pid}
          :none -> :none
        end
    end
  end

  # We recursively try to find one of the given PIDs which owns the
  # given module. We do this instead of, say, building a match spec
  # because this is significantly more performant. With ~10k ownership
  # rows in ETS, this takes ~500µs with a match spec and < ~10µs for common
  # cases with this recursive lookup.
  defp find_owner(_pids = [], _module) do
    :none
  end

  defp find_owner([pid | pids], module) do
    case :ets.lookup(@table, {pid, module}) do
      [] -> find_owner(pids, module)
      [{{^pid, ^module}, owner_pid}] -> {:ok, owner_pid}
    end
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    {:ok, %State{}}
  end

  def handle_cast({:exit, pid}, state) do
    {:noreply, clear_data_from_pid(pid, state)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_state =
      if MapSet.member?(state.verify_on_exit, pid) do
        state
      else
        clear_data_from_pid(pid, state)
      end

    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    IO.puts("handle_info with #{inspect(msg)} not handled")
    {:noreply, state}
  end

  defp clear_data_from_pid(pid, state) do
    expectations = Map.delete(state.expectations, pid)
    stubs = Map.delete(state.stubs, pid)

    select = [{{{pid, :_}, :_}, [], [true]}, {{{:_, :_}, pid}, [], [true]}]

    :ets.select_delete(@table, select)

    Coordinator.clear_global_owner(pid)

    call_history = Map.delete(state.call_history, pid)

    %{state | expectations: expectations, stubs: stubs, call_history: call_history}
  end

  defp find_stub(stubs, module, fn_name, arity, caller) do
    case get_in(stubs, [caller, {module, fn_name, arity}]) do
      func when is_function(func) -> {:ok, func}
      nil -> :unexpected
    end
  end

  defp get_call_history(state, caller, module, fn_name, arity) do
    get_in(state.call_history, [Access.key(caller, %{}), {module, fn_name, arity}])
  end

  defp put_call_history(state, caller, module, fn_name, arity, args) do
    call_history = get_call_history(state, caller, module, fn_name, arity) || []

    %{
      state
      | call_history:
          put_in(
            state.call_history,
            [Access.key(caller, %{}), {module, fn_name, arity}],
            [
              args | call_history
            ]
          )
    }
  end

  def handle_call({:apply, owner_pid, module, fn_name, arity, args}, _from, state) do
    caller = owner_pid

    case get_in(state.expectations, [Access.key(caller, %{}), {module, fn_name, arity}]) do
      [expectation | _] = expectations ->
        case apply_call_to_expectations(expectations, expectation) do
          {:ok, func, new_expectations} ->
            expectations =
              put_in(state.expectations, [caller, {module, fn_name, arity}], new_expectations)

            # Track call history
            state = put_call_history(state, caller, module, fn_name, arity, args)

            {:reply, {:ok, func}, %{state | expectations: expectations}}

          {:unexpected, num_calls, num_applied_calls} ->
            {:reply, {:unexpected, num_calls, num_applied_calls}, state}
        end

      expectations ->
        case {find_stub(state.stubs, module, fn_name, arity, caller), expectations} do
          {{:ok, func}, _} ->
            # Track call history for stubs too
            state = put_call_history(state, caller, module, fn_name, arity, args)

            {:reply, {:ok, func}, state}

          {:unexpected, []} ->
            # expectations for this mfa existed but they have all been fulfilled
            {:reply, {:unexpected, :fulfilled}, state}

          {:unexpected, nil} ->
            # no expectations were ever defined for this mfa
            # This case happens when another mfa was set-up
            {:reply, :original, state}
        end
    end
  end

  def handle_call({:stub, module, fn_name, func, arity, owner}, _from, state) do
    register_owner(owner, module, state, fn ->
      func = maybe_typecheck_func(module, fn_name, func)

      %{
        state
        | stubs: put_in(state.stubs, [Access.key(owner, %{}), {module, fn_name, arity}], func)
      }
    end)
  end

  def handle_call({:stub, module, owner}, _from, state) do
    register_owner(owner, module, state, fn ->
      internal_functions = [__info__: 1, module_info: 0, module_info: 1]

      stubs =
        module.module_info(:exports)
        |> Enum.filter(&(&1 not in internal_functions))
        |> Enum.reduce(state.stubs, fn {fn_name, arity}, stubs ->
          func = stub_function(module, fn_name, arity)
          put_in(stubs, [Access.key(owner, %{}), {module, fn_name, arity}], func)
        end)

      %{state | stubs: stubs}
    end)
  end

  def handle_call({:stub_with, mocked_module, mocking_module, owner}, _from, state) do
    register_owner(owner, mocked_module, state, fn ->
      original_module = Mimic.Module.original(mocked_module)

      internal_functions = [__info__: 1, module_info: 0, module_info: 1]

      mocked_public_functions =
        original_module.module_info(:exports)
        |> Enum.filter(&(&1 not in internal_functions))
        |> MapSet.new()

      mocking_public_functions =
        mocking_module.module_info(:exports)
        |> Enum.filter(&(&1 not in internal_functions))
        |> MapSet.new()

      will_be_mocked_functions =
        MapSet.intersection(mocking_public_functions, mocked_public_functions)

      will_be_stubbed_functions =
        MapSet.difference(mocked_public_functions, mocking_public_functions)

      stubs =
        will_be_mocked_functions
        |> Enum.reduce(state.stubs, fn {fn_name, arity}, stubs ->
          func = anonymize_module_function(mocking_module, fn_name, arity)
          func = maybe_typecheck_func(mocked_module, fn_name, func)
          put_in(stubs, [Access.key(owner, %{}), {mocked_module, fn_name, arity}], func)
        end)

      stubs =
        will_be_stubbed_functions
        |> Enum.reduce(stubs, fn {fn_name, arity}, stubs ->
          func = stub_function(mocked_module, fn_name, arity)
          put_in(stubs, [Access.key(owner, %{}), {mocked_module, fn_name, arity}], func)
        end)

      %{state | stubs: stubs}
    end)
  end

  def handle_call({:expect, {module, fn_name, func, arity}, num_calls, owner}, _from, state) do
    register_owner(owner, module, state, fn ->
      func = maybe_typecheck_func(module, fn_name, func)

      expectation = %Expectation{func: func, num_calls: num_calls}

      expectations =
        update_in(
          state.expectations,
          [Access.key(owner, %{}), {module, fn_name, arity}],
          &((&1 || []) ++ [expectation])
        )

      %{state | expectations: expectations}
    end)
  end

  def handle_call({:verify, pid}, _from, state) do
    expectations = state.expectations[pid] || %{}

    pending =
      for {{module, fn_name, arity}, mfa_expectations} <- expectations,
          expectation = %Expectation{num_applied_calls: num_applied_calls, num_calls: num_calls} <-
            mfa_expectations,
          num_calls != num_applied_calls do
        {{module, fn_name, arity}, expectation.num_calls, expectation.num_applied_calls}
      end

    {:reply, pending, state}
  end

  def handle_call({:verify_on_exit, pid}, _from, state) do
    {:reply, :ok, %{state | verify_on_exit: MapSet.put(state.verify_on_exit, pid)}}
  end

  def handle_call(:soft_reset, _from, state) do
    {:reply, :ok, %{state | expectations: %{}, stubs: %{}}}
  end

  def handle_call({:get_calls, {module, fn_name, arity}, owner_pid}, _from, state) do
    case pop_in(state.call_history, [Access.key(owner_pid, %{}), {module, fn_name, arity}]) do
      {calls, call_history} when is_list(calls) ->
        {:reply, {:ok, Enum.reverse(calls)}, %{state | call_history: call_history}}

      {nil, _} ->
        {:reply, {:ok, []}, state}
    end
  end

  defp maybe_typecheck_func(module, fn_name, func) do
    case module.__mimic_info__() do
      {:ok, %{type_check: true}} ->
        Mimic.TypeCheck.wrap(module, fn_name, func)

      _ ->
        func
    end
  end

  defp apply_call_to_expectations(
         expectations,
         expectation = %Expectation{num_applied_calls: num_applied_calls, num_calls: num_calls}
       ) do
    cond do
      num_applied_calls + 1 == num_calls ->
        {:ok, expectation.func, tl(expectations)}

      num_applied_calls + 1 < num_calls ->
        {:ok, expectation.func,
         [%{expectation | num_applied_calls: num_applied_calls + 1} | tl(expectations)]}

      true ->
        {:unexpected, expectation.num_calls, expectation.num_applied_calls + 1}
    end
  end

  # Shared scaffolding for the stub/stub_with/expect handlers: gate on the
  # current mode, monitor the owner, register its ownership row, then run
  # `build_state` (which computes the stubs/expectations for this owner) and
  # reply. Keeping this in one place means the mode/ownership atomicity fixes
  # land here rather than in four near-identical clauses.
  defp register_owner(owner, module, state, build_state) do
    if valid_mode?(owner) do
      monitor_if_not_verify_on_exit(owner, state.verify_on_exit)

      :ets.insert_new(@table, {{owner, module}, owner})

      {:reply, {:ok, module}, build_state.()}
    else
      {:reply, {:error, :not_global_owner}, state}
    end
  end

  defp valid_mode?(caller) do
    case :ets.lookup(@table, :mode) do
      [{:mode, :private}] -> true
      [{:mode, :global, global_pid}] -> global_pid == caller
    end
  end

  def monitor_if_not_verify_on_exit(pid, verify_on_exit) do
    unless MapSet.member?(verify_on_exit, pid) do
      Process.monitor(pid)
    end
  end

  defp stub_function(module, fn_name, arity) do
    args =
      0..arity
      |> Enum.to_list()
      |> tl
      |> Enum.map(fn i -> Macro.var(String.to_atom("arg_#{i}"), nil) end)

    clause =
      quote do
        unquote_splicing(args) ->
          mfa = Exception.format_mfa(unquote(module), unquote(fn_name), unquote(args))

          raise Mimic.UnexpectedCallError,
                "Stub! Unexpected call to #{mfa} from #{inspect(self())}"
      end

    {fun, _} = Code.eval_quoted({:fn, [], clause})
    fun
  end

  defp anonymize_module_function(module, fn_name, arity) do
    args =
      0..arity
      |> Enum.to_list()
      |> tl
      |> Enum.map(fn i -> Macro.var(String.to_atom("arg_#{i}"), nil) end)

    clause =
      quote do
        unquote_splicing(args) ->
          apply(unquote(module), unquote(fn_name), [unquote_splicing(args)])
      end

    {fun, _} = Code.eval_quoted({:fn, [], clause})
    fun
  end
end
