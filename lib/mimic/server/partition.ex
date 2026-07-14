defmodule Mimic.Server.Partition do
  use GenServer
  alias Mimic.Cover
  alias Mimic.Server
  @moduledoc false

  defmodule State do
    @moduledoc false
    defstruct verify_on_exit: MapSet.new(),
              stubs: %{},
              expectations: %{},
              modules_beam: %{},
              modules_to_be_copied: MapSet.new(),
              reset_tasks: %{},
              modules_opts: %{},
              call_history: %{}
  end

  defmodule Expectation do
    @moduledoc false
    defstruct func: nil, num_applied_calls: 0, num_calls: nil
  end

  @long_timeout Application.compile_env(:mimic, :server_timeout, 60_000)

  def start_link(_opts) do
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

  # Reset task has successfully finished
  def handle_info({ref, :ok}, state) do
    reset_tasks = Map.delete(state.reset_tasks, ref)

    {:noreply, %{state | reset_tasks: reset_tasks}}
  end

  def handle_info(msg, state) do
    IO.puts("handle_info with #{inspect(msg)} not handled")
    {:noreply, state}
  end

  def handle_call({:apply, owner_pid, module, fn_name, arity, args}, _from, state) do
    caller =
      case Server.mode_info() do
        {:private, _} -> owner_pid
        {:global, global_pid} -> global_pid
      end

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
    with {:ok, state} <- ensure_module_copied(module, state),
         true <- valid_mode?(owner),
         func <- maybe_typecheck_func(module, fn_name, func) do
      monitor_if_not_verify_on_exit(owner, state.verify_on_exit)

      Server.insert_new_owner(module, owner, owner)

      {:reply, {:ok, module},
       %{
         state
         | stubs: put_in(state.stubs, [Access.key(owner, %{}), {module, fn_name, arity}], func)
       }}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      false ->
        {:reply, {:error, :not_global_owner}, state}
    end
  end

  def handle_call({:stub, module, owner}, _from, state) do
    with {:ok, state} <- ensure_module_copied(module, state),
         true <- valid_mode?(owner) do
      monitor_if_not_verify_on_exit(owner, state.verify_on_exit)

      Server.insert_new_owner(module, owner, owner)

      internal_functions = [__info__: 1, module_info: 0, module_info: 1]

      stubs =
        module.module_info(:exports)
        |> Enum.filter(&(&1 not in internal_functions))
        |> Enum.reduce(state.stubs, fn {fn_name, arity}, stubs ->
          func = stub_function(module, fn_name, arity)
          put_in(stubs, [Access.key(owner, %{}), {module, fn_name, arity}], func)
        end)

      {:reply, {:ok, module}, %{state | stubs: stubs}}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      false ->
        {:reply, {:error, :not_global_owner}, state}
    end
  end

  def handle_call({:stub_with, mocked_module, mocking_module, owner}, _from, state) do
    with {:ok, state} <- ensure_module_copied(mocked_module, state),
         true <- valid_mode?(owner) do
      monitor_if_not_verify_on_exit(owner, state.verify_on_exit)

      Server.insert_new_owner(mocked_module, owner, owner)

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

      {:reply, {:ok, mocked_module}, %{state | stubs: stubs}}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      false ->
        {:reply, {:error, :not_global_owner}, state}
    end
  end

  def handle_call({:expect, {module, fn_name, func, arity}, num_calls, owner}, _from, state) do
    with {:ok, state} <- ensure_module_copied(module, state),
         true <- valid_mode?(owner),
         func <- maybe_typecheck_func(module, fn_name, func) do
      monitor_if_not_verify_on_exit(owner, state.verify_on_exit)

      Server.insert_new_owner(module, owner, owner)

      expectation = %Expectation{func: func, num_calls: num_calls}

      expectations =
        update_in(
          state.expectations,
          [Access.key(owner, %{}), {module, fn_name, arity}],
          &((&1 || []) ++ [expectation])
        )

      {:reply, {:ok, module}, %{state | expectations: expectations}}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      false ->
        {:reply, {:error, :not_global_owner}, state}
    end
  end

  def handle_call({:allow, module, owner_pid, allowed_pid}, _from, state) do
    case Server.mode_info() do
      {:private, _} ->
        actual_owner_pid =
          case Server.lookup_owner(module, owner_pid) do
            {:ok, owner_pid} -> owner_pid
            :error -> owner_pid
          end

        Server.insert_owner(module, allowed_pid, actual_owner_pid)

        {:reply, {:ok, module}, state}

      {:global, _} ->
        {:reply, {:error, :global}, state}
    end
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
    state = %{state | expectations: %{}, stubs: %{}, call_history: %{}}
    {:reply, :ok, state}
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

    # All modules in this partition have been reset. We should await all tasks now
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
          {:ok, state} = ensure_module_copied(module, state)
          state
        else
          state
        end

      {:reply, :ok, state}
    end
  end

  def handle_call({:get_calls, {module, fn_name, arity}, owner_pid, caller_pids}, _from, state) do
    caller_pid =
      case Server.allowed_pid(caller_pids, module) do
        {:ok, owner_pid} -> owner_pid
        _ -> owner_pid
      end

    case ensure_module_copied(module, state) do
      {:ok, state} ->
        case pop_in(state.call_history, [Access.key(caller_pid, %{}), {module, fn_name, arity}]) do
          {calls, call_history} when is_list(calls) ->
            {:reply, {:ok, Enum.reverse(calls)}, %{state | call_history: call_history}}

          {nil, _} ->
            {:reply, {:ok, []}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp clear_data_from_pid(pid, state) do
    expectations = Map.delete(state.expectations, pid)
    stubs = Map.delete(state.stubs, pid)

    Server.clear_ownership(pid)

    if Server.global_owner?(pid) do
      Server.set_private_mode()
    end

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

  defp maybe_typecheck_func(module, fn_name, func) do
    case module.__mimic_info__() do
      {:ok, %{type_check: true}} ->
        Mimic.TypeCheck.wrap(module, fn_name, func)

      _ ->
        func
    end
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

  defp valid_mode?(caller) do
    case Server.mode_info() do
      {:private, _} -> true
      {:global, global_pid} -> global_pid == caller
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
