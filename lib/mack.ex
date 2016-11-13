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
end
