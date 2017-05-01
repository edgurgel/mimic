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
    contents =
      quote do
        use Mack.Proxy
      end

    rename_module(module, backup_module)
    Code.compiler_options(ignore_module_conflict: true)
    Module.create(module, contents, Macro.Env.location(__ENV__))
    Code.compiler_options(ignore_module_conflict: false)
    Mack.Supervisor.start_proxy(module, backup_module, opts)
    :ok
  end

  defp backup_module(module) do
    "#{module}_backup_mack" |> String.to_atom
  end

  def unload(module) do
    Proxy.stop(module)
    :code.purge(module)
    :code.delete(module)
    {:module, ^module} = :code.ensure_loaded(module)
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

  defp rename_module(module, new_module) do
    beam_file = case :code.get_object_code(module) do
                  {_, binary, _filename} -> binary;
                  _error                  -> throw {:object_code_not_found, module}
                end

    result = case :beam_lib.chunks(beam_file, [:abstract_code]) do
      {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} -> forms;
      {:ok, {_, [{:abstract_code, :no_abstract_code}]}} -> throw :no_abstract_code
    end |> rename_attribute(new_module)

    case :compile.forms(result, [:return_errors]) do
        {:ok, module_name, binary} ->
            load_binary(module_name, binary)
            binary
        {:ok, module_name, binary, _Warnings} ->
            load_binary(module_name, binary)
            Binary
        error ->
            exit({:compile_forms, error})
    end
  end

  defp load_binary(module, binary) do
    case :code.load_binary(module, '', binary) do
        {:module, ^module}  -> :ok;
        {:error, reason} -> exit({:error_loading_module, module, reason})
        _ -> :yolo
    end
  end

  defp rename_attribute([{:attribute, line, :module, {_, vars}} | t], new_name) do
    [{:attribute, line, :module, {new_name, vars}} | t]
  end
  defp rename_attribute([{:attribute, line, :module, _} | t], new_name) do
    [{:attribute, line, :module, new_name} | t]
  end
  defp rename_attribute([h | t], new_name), do: [h | rename_attribute(t, new_name)]

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
