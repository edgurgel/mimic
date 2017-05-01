defmodule Mack do
  alias Mack.Proxy

  use Application

  @doc false
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    children = [supervisor(Mack.Supervisor, [])]
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end

  def new(module, opts \\ []) do
    backup_module = backup_module(module)
    Mack.Module.replace!(module, backup_module)
    Mack.Supervisor.start_proxy(module, backup_module, opts)
    :ok
  end

  defp backup_module(module) do
    "#{module}_backup_mack" |> String.to_atom
  end

  def unload(module) do
    Proxy.stop(module)
    Mack.Module.clear!(module)
  end

  @doc """
  Reset stub and history on `module`
  """
  @spec reset(module) :: :ok
  def reset(module), do: Proxy.reset(module)

  @doc """
  Return the history of calls that `module` received
  """
  @spec history(module) :: [{pid, atom, list, term}]
  def history(module), do: Proxy.history(module)

  @doc """
  Check if `module.func(args)` was called and returned `result`
  """
  @spec received?(module, atom, list, term) :: boolean
  def received?(module, func, args, result) do
    Enum.find(Proxy.history(module), fn {_pid, ^func, ^args, {:value, ^result}} -> true
                                        _ -> false
    end)
  end

  @doc """
  allow `module` to receive to call `func` with `args` and returning `result
  """
  @spec allow(module, atom, list, term | function) :: :ok
  def allow(module, func, args, result), do: Proxy.allow(module, func, args, result)

  @doc """
  allow `module` to receive to call `func` with `args` and returning `result
  """
  @spec allow(module, atom, list, function) :: :ok
  def allow(module, func, result) when is_function(result), do: Proxy.allow(module, func, result)

  @doc """
  allow/2 can receive a do clause:

  allow TestModule.sum(x, y) do
    x * y
  end
  """
  defmacro allow(call, do: clause) do
    {{:., _, [module, func]}, _, args} = call
    underscore_args = Enum.map(args, fn _x -> :_ end)
    module = Macro.expand(module, __CALLER__)
    quote do
      allow(unquote(module), unquote(func), unquote(underscore_args), fn (unquote_splicing(args)) -> unquote(clause) end)
    end
  end
end
