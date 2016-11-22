defmodule Mack do
  alias Mack.Proxy

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    children = [supervisor(Mack.Supervisor, [])]
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end

  def new(module) do
    contents =
      quote do
        use Mack.Proxy
      end

    Code.compiler_options(ignore_module_conflict: true)
    Module.create(module, contents, Macro.Env.location(__ENV__))
    Code.compiler_options(ignore_module_conflict: false)
    Mack.Supervisor.start_proxy(module)
    :ok
  end

  def reset(module), do: Proxy.reset(module)

  def history(module), do: Proxy.history(module)

  def allow(module, func, args, result), do: Proxy.allow(module, func, args, result)

  # defmacro allow(call, do: clause) do
    # IO.puts "allow/2"
    # IO.inspect [call: call]
    # IO.inspect [clause: clause]
    # # {{:., [line: 40], [{:__aliases__, [counter: 0, line: 40], [:TestModule]}, :sum]}, [line: 40], [1, 1]}
    # {{:., _, [module, func]}, _, args} = call
    # # IO.inspect Macro.expand(module, __CALLER__)
    # # IO.inspect [module, func, args, result_function]
    # # funtion = unquote(result_function)
    # # IO.inspect [module, func, args, result_function]
    # # IO.inspect args
    # module = Macro.expand(module, __CALLER__)
    # # quote do
      # # allow(unquote(module), unquote(func), unquote(args), unquote(result_function))
    # # end
  # end
  defmacro allow(call, result_function) do
    {{:., _, [module, func]}, _, args} = call
    module = Macro.expand(module, __CALLER__)
    quote do
      allow(unquote(module), unquote(func), unquote(args), unquote(result_function))
    end
  end
end
