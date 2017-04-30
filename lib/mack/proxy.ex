defmodule Mack.Proxy do
  use GenServer
  import List, only: [to_tuple: 1]

  defmodule State do
    defstruct history: [], module: :undefined, stubs: nil,
              passthrough: false, backup_module: :undefined
  end

  def start_link(module, backup_module, opts) do
    GenServer.start_link(__MODULE__, [module, backup_module, opts], name: name(module))
  end

  def init([module, backup_module, opts]) do
    passthrough = Keyword.get(opts, :passthrough, false)
    {:ok, %State{module: module, stubs: [], backup_module: backup_module, passthrough: passthrough}}
  end

  def handle_call({:apply, func, args}, {pid, _ref} = _from, state = %State{ module: module, history: history }) do
    result = eval_apply(module, func, args, state.stubs)
    result = cond do
              {:error, %UndefinedFunctionError{}} && state.passthrough -> Kernel.apply(state.backup_module, func, args)
              true -> result
            end
    {:reply, result, %{state | history: [{pid, func, args, result} | history]}}
  end
  def handle_call({:allow, func, args, result}, _from, state) do
    {:reply, :ok, %{state | stubs: [{{func, args}, result} | state.stubs]}}
  end
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | stubs: [], history: [] }}
  end
  def handle_call(:history, _from, state), do: {:reply, state.history, state}
  def handle_call(:stop, _from, state), do: {:stop, :normal, :ok, state}

  defp eval_apply(module, func, args, stubs) do
    arity = Enum.count(args)
    case find_result(func, args, stubs) do
      nil -> {:error, undefined_function_exception(module, func, arity, args)}
      {{^func, _args}, result_fn} when is_function(result_fn, arity) -> apply_fn(result_fn, args)
      {{^func, _args}, result} -> {:value, result}
    end
  end

  defp apply_fn(function, args) do
    try do
      value = apply(function, args)
      {:value, value}
    catch
      value -> {:throw, value}
    rescue
      error -> {:error, error}
    end
  end

  defp undefined_function_exception(module, func, arity, args) do
    opts = [module: module, function: func, arity: arity,
            reason: "function not available: #{inspect(module)}.#{func}(#{inspect(args)}) "]
    UndefinedFunctionError.exception(opts)
  end

  defp find_result(func, args, stubs) do
    Enum.find stubs, fn
      {{^func, args_to_apply}, _result} ->
        case :ets.test_ms(to_tuple(args), [{to_tuple(args_to_apply), [], [true]}]) do
          {:ok, true} -> true
          _ -> false
        end
      _ -> false
    end
  end

  def apply(module, func, args) do
    case GenServer.call(name(module), {:apply, func, args}) do
      {:error, exception} -> raise exception
      {:throw, value} -> throw value
      {:value, value} -> value
    end
  end

  def allow(module, func, args, result) do
    GenServer.call(name(module), {:allow, func, args, result})
  end

  def allow(module, func, result) when is_function(result) do
    arity = :erlang.fun_info(result)[:arity]
    args = Enum.map(arity..1, fn _ -> :_ end)
    GenServer.call(name(module), {:allow, func, args, result})
  end

  def reset(module), do: GenServer.call(name(module), :reset)

  def history(module) do
    GenServer.call(name(module), :history)
  end

  def stop(module) do
    GenServer.call(name(module), :stop)
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
