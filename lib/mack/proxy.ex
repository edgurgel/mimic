defmodule Mack.Proxy do
  use GenServer
  import List, only: [to_tuple: 1]

  defmodule State do
    defstruct history: [],
              module: :undefined,
              stubs: [],
              expectations: [],
              passthrough: true,
              backup_module: :undefined
  end

  defmodule Stub do
    defstruct ~w(fn_name func arity owner)a
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

  def handle_call({:apply, fn_name, args}, {caller, _ref} = from, state) do
    parent = self()

    spawn_link(fn ->
      result = do_apply(fn_name, args, caller, state)
      send(parent, {:apply_result, from, {caller, fn_name, args, result}})
    end)

    {:noreply, state}
  end

  def handle_call({:stub, fn_name, func, arity, owner}, _from, state) do
    stub = %Stub{fn_name: fn_name, func: func, arity: arity, owner: owner}

    if :erlang.function_exported(state.backup_module, fn_name, arity) do
      {:reply, :ok, %{state | stubs: [stub | state.stubs]}}
    else
      error = %Mack.Error{module: state.module, fn_name: fn_name, arity: arity}
      {:reply, {:error, error}, state}
    end
  end

  def terminate(_), do: IO.puts("terminating")

  defp do_apply(fn_name, args, caller, state) do
    result = eval_apply(state.module, fn_name, args, caller, state.stubs)

    if match?({:error, %UndefinedFunctionError{}}, result) && state.passthrough do
      apply_mfa(state.backup_module, fn_name, args)
    else
      result
    end
  end

  defp eval_apply(module, fn_name, args, caller, stubs) do
    arity = Enum.count(args)

    case find_result(fn_name, arity, caller, stubs) do
      nil -> {:error, undefined_function_exception(module, fn_name, arity, args)}
      %Stub{func: func} -> apply_fn(func, args)
    end
  end

  defp find_result(fn_name, arity, caller, stubs) do
    Enum.find(stubs, fn
      %Stub{fn_name: ^fn_name, arity: ^arity, owner: ^caller} -> true
      _ -> false
    end)
  end

  defp apply_fn(function, args) do
    try do
      value = Kernel.apply(function, args)
      {:value, value}
    rescue
      error -> {:error, error}
    catch
      :exit, reason -> {:exit, reason}
      value -> {:throw, value}
    end
  end

  defp apply_mfa(module, function, args) do
    try do
      value = Kernel.apply(module, function, args)
      {:value, value}
    rescue
      error -> {:error, error}
    catch
      :exit, reason -> {:exit, reason}
      value -> {:throw, value}
    end
  end

  defp undefined_function_exception(module, func, arity, args) do
    args = Enum.map(args, &inspect(&1)) |> Enum.join(",")

    opts = [
      module: module,
      function: func,
      arity: arity,
      reason: "function not available: #{inspect(module)}.#{func}(#{args})"
    ]

    UndefinedFunctionError.exception(opts)
  end

  def apply(module, fn_name, args) do
    case GenServer.call(name(module), {:apply, fn_name, args}, :infinity) do
      {:value, value} -> value
      {:error, exception} -> raise exception
      {:throw, value} -> throw(value)
      {:exit, reason} -> exit(reason)
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
