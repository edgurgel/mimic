defmodule Mack.Proxy do
  use GenServer

  defmodule State do
    defstruct history: [], module: :undefined, stubs: nil
  end

  def start_link(module) do
    GenServer.start_link(__MODULE__, module, name: name(module))
  end

  def init(module) do
    stubs = :ets.new(module, [:private, :set])
    {:ok, %State{module: module, stubs: stubs}}
  end

  def handle_call({:apply, func, args}, {pid, _ref} = _from, state = %State{ module: module, history: history }) do
    arity = Enum.count(args)
    reply = case :ets.lookup(state.stubs, {func, args}) do
      [] ->
        arity = Enum.count(args)
        opts = [module: module, function: func, arity: arity,
                reason: "function not available: #{inspect(module)}.#{func}(#{inspect(args)}) "]
        UndefinedFunctionError.exception(opts)
      [{_, result_fn}] when is_function(result_fn, arity) -> apply(result_fn, args)
      [{_, result}] -> result
    end
    {:reply, reply, %{state | history: [{pid, func, args, reply} | history]}}
  end
  def handle_call({:allow, func, args, result}, _from, state) do
    :ets.insert(state.stubs, {{func, args}, result})
    {:reply, :ok, state}
  end
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(state.stubs)
    {:reply, :ok, %{state | history: [] }}
  end
  def handle_call(:history, _from, state), do: {:reply, state.history, state}

  def apply(module, func, args) do
    case GenServer.call(name(module), {:apply, func, args}) do
      %UndefinedFunctionError{} = exception -> raise exception
      result -> result
    end
  end

  def allow(module, func, args, result) do
    GenServer.call(name(module), {:allow, func, args, result})
  end

  def reset(module), do: GenServer.call(name(module), :reset)

  def history(module) do
    GenServer.call(name(module), :history)
  end

  def name(module), do: Module.concat(Mack.Proxy, module)

  @doc false
  defmacro __using__(_) do
    quote do
      @doc false
      def unquote(:"$handle_undefined_function")(func, args) do
        Mack.Proxy.apply(__MODULE__, func, args)
      end
    end
  end
end
