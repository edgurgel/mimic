defmodule Mack do
  alias Mack.Proxy

  use Application

  defmodule UnexpectedCallError do
    defexception [:message]
  end

  defmodule Error do
    defexception ~w(module fn_name arity)a

    def message(e) do
      "#{inspect(e.module)}.#{e.func}/#{e.arity} cannot be stubbed as original module does not export such function"
    end
  end

  @doc false
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    children = [supervisor(Mack.Supervisor, [])]
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end

  def stub(module, fn_name, func) do
    Mack.Proxy.stub(module, fn_name, func)
    module
  end

  def expect(module, fn_name, func) do
    Mack.Proxy.expect(module, fn_name, func)
    module
  end

  def defmock(module, opts \\ []) do
    backup_module = backup_module(module)
    Mack.Module.replace!(module, backup_module)
    Mack.Supervisor.start_proxy(module, backup_module, opts)
    :ok
  end

  defp backup_module(module) do
    "#{module}_backup_mack" |> String.to_atom()
  end

  # def unload(module) do
  # Proxy.stop(module)
  # Mack.Module.clear!(module)
  # end

  def verify_on_exit!(_context \\ %{}) do
    pid = self()
    Mack.Proxy.verify_on_exit(pid)

    ExUnit.Callbacks.on_exit(Mack, fn ->
      verify_mock_or_all!(pid, :all)
      # Mack.Server.exit(pid) #?
    end)
  end

  def verify_mock_or_all!(pid, :all) do
  end
end
