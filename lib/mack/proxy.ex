defmodule Mack.Proxy do
  use GenServer

  defmodule State do
    defstruct history: [],
              module: :undefined,
              stubs: %{},
              expectations: %{},
              passthrough: true,
              backup_module: :undefined
  end

  defmodule Expectation do
    defstruct ~w(fn_name func arity)a
  end

  def stub(module, fn_name, func) do
    arity = :erlang.fun_info(func)[:arity]
    GenServer.call(name(module), {:stub, fn_name, func, arity, self()})
  end

  def expect(module, fn_name, func) do
    arity = :erlang.fun_info(func)[:arity]
    GenServer.call(name(module), {:expect, fn_name, func, arity, self()})
  end

  def start_link(module, backup_module, opts) do
    GenServer.start_link(__MODULE__, [module, backup_module, opts], name: name(module))
  end

  def init([module, backup_module, opts]) do
    passthrough = Keyword.get(opts, :passthrough, true)
    {:ok, %State{module: module, backup_module: backup_module, passthrough: passthrough}}
  end

  def handle_info({:apply_result, from, {pid, fn_name, args, result}}, state) do
    GenServer.reply(from, result)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.puts("handle_info with #{inspect(msg)} not handled")
    {:noreply, state}
  end

  defp find_stub(stubs, fn_name, arity, caller) do
    case Map.get(stubs, {fn_name, arity, caller}) do
      func when is_function(func) -> func
      nil -> :unexpected
    end
  end

  def handle_call({:apply, fn_name, args, arity}, {caller, _ref} = from, state) do
    case Map.get(state.expectations, {fn_name, arity, caller}) do
      [%Expectation{func: func} | tail] ->
        {:reply, {:ok, func}, state}
      nil ->
        func = find_stub(state.stubs, fn_name, arity, caller)
        {:reply, {:ok, func}, state}
    end
  end

  def handle_call({:stub, fn_name, func, arity, owner}, _from, state) do
    if :erlang.function_exported(state.backup_module, fn_name, arity) do
      {:reply, :ok, %{state | stubs: Map.put(state.stubs, {fn_name, arity, owner}, func) }}
    else
      error = %Mack.Error{module: state.module, fn_name: fn_name, arity: arity}
      {:reply, {:error, error}, state}
    end
  end

  def handle_call({:expect, fn_name, func, arity, owner}, _from, state) do
    expectation = %Expectation{fn_name: fn_name, func: func, arity: arity}

    if :erlang.function_exported(state.backup_module, fn_name, arity) do
      expectations = update_in(state.expectations, [{fn_name, arity, owner}], & (&1 || []) ++ [expectation])
      {:reply, :ok, %{state | expectations: expectations}}
    else
      error = %Mack.Error{module: state.module, fn_name: fn_name, arity: arity}
      {:reply, {:error, error}, state}
    end
  end

  def apply(module, fn_name, args) do
    arity = Enum.count(args)

    case GenServer.call(name(module), {:apply, fn_name, args, arity}, :infinity) do
      {:ok, func} ->
        Kernel.apply(func, args)

      :unexpected ->
        mfa = Exception.format_mfa(module, fn_name, arity)

        raise Mack.UnexpectedCallError, "Unexpected call to #{mfa} from #{inspect(self())}"
    end
  end

  @doc """
  Proxy module name
  """
  @spec name(module) :: module
  def name(module), do: Module.concat(Mack.Proxy, module)

  @doc false
  defmacro __using__(_) do
    quote do
      @doc false
      def unquote(:"$handle_undefined_function")(fn_name, args) do
        Mack.Proxy.apply(__MODULE__, fn_name, args)
      end
    end
  end
end
