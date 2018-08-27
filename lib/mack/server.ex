defmodule Mack.Server do
  use GenServer

  defmodule State do
    defstruct pids: MapSet.new(),
              modules: MapSet.new(),
              stubs: %{},
              expectations: %{}
  end

  defmodule Expectation do
    defstruct ~w(func)a
  end

  def mock(module) do
    GenServer.call(__MODULE__, {:mock, module})
  end

  def verify(pid) do
    GenServer.call(__MODULE__, {:verify, pid})
  end

  def stub(module, fn_name, func) do
    arity = :erlang.fun_info(func)[:arity]
    GenServer.call(__MODULE__, {:stub, module, fn_name, func, arity, self()})
  end

  def expect(module, fn_name, func) do
    arity = :erlang.fun_info(func)[:arity]
    GenServer.call(__MODULE__, {:expect, module, fn_name, func, arity, self()})
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]), do: {:ok, %State{}}

  def handle_info(msg, state) do
    IO.puts("handle_info with #{inspect(msg)} not handled")
    {:noreply, state}
  end

  defp find_stub(stubs, module, fn_name, arity, caller) do
    case get_in(stubs, [caller, {module, fn_name, arity}]) do
      func when is_function(func) -> {:ok, func}
      nil -> :unexpected
    end
  end

  def handle_call({:apply, module, fn_name, arity}, {caller, _ref} = _from, state) do
    if MapSet.member?(state.pids, caller) do
      case get_in(state.expectations, [Access.key(caller, %{}), {module, fn_name, arity}]) do
        [%Expectation{func: func} | tail] ->
          expectations = put_in(state.expectations, [caller, {module, fn_name, arity}], tail)
          {:reply, {:ok, func}, %{state | expectations: expectations}}

        _ ->
          result = find_stub(state.stubs, module, fn_name, arity, caller)
          {:reply, result, state}
      end
    else
      {:reply, :original, state}
    end
  end

  def handle_call({:stub, module, fn_name, func, arity, owner}, _from, state) do
    if MapSet.member?(state.modules, module) do
      {:reply, :ok,
       %{
         state
         | stubs: put_in(state.stubs, [Access.key(owner, %{}), {module, fn_name, arity}], func),
           pids: MapSet.put(state.pids, owner)
       }}
    else
      {:reply, {:error, :not_mocked}, state}
    end
  end

  def handle_call({:expect, module, fn_name, func, arity, owner}, _from, state) do
    if MapSet.member?(state.modules, module) do
      expectation = %Expectation{func: func}

      expectations =
        update_in(
          state.expectations,
          [Access.key(owner, %{}), {module, fn_name, arity}],
          &((&1 || []) ++ [expectation])
        )

      {:reply, :ok, %{state | expectations: expectations, pids: MapSet.put(state.pids, owner)}}
    else
      {:reply, {:error, :not_mocked}, state}
    end
  end

  def handle_call({:mock, module}, _from, state) do
    {:reply, :ok, %{state | modules: MapSet.put(state.modules, module)}}
  end

  def handle_call({:verify, pid}, _from, state) do
    expectations = state.expectations[pid] || %{}

    pending =
      for {{module, fn_name, arity}, mfa_expectations} <- expectations,
          _mfa_expectation <- mfa_expectations do
            {module, fn_name, arity}
      end
    {:reply, pending, state}
  end

  def apply(module, fn_name, args) do
    arity = Enum.count(args)
    original_module = original_module(module)

    if :erlang.function_exported(original_module, fn_name, arity) do
      case GenServer.call(__MODULE__, {:apply, module, fn_name, arity}, :infinity) do
        {:ok, func} ->
          Kernel.apply(func, args)

        :original ->
          Kernel.apply(original_module(module), fn_name, args)

        :unexpected ->
          mfa = Exception.format_mfa(module, fn_name, arity)

          raise Mack.UnexpectedCallError, "Unexpected call to #{mfa} from #{inspect(self())}"
      end
    else
      raise Mack.Error, module: module, fn_name: fn_name, arity: arity
    end
  end

  def original_module(module) do
    "#{module}_original_module" |> String.to_atom()
  end

  @doc false
  defmacro __using__(_) do
    quote do
      @doc false
      def unquote(:"$handle_undefined_function")(fn_name, args) do
        Mack.Server.apply(__MODULE__, fn_name, args)
      end
    end
  end
end
