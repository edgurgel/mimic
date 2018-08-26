defmodule Mack do
  alias Mack.Server

  defmodule UnexpectedCallError do
    defexception [:message]
  end

  defmodule Error do
    defexception ~w(module fn_name arity)a

    def message(e) do
      mfa = Exception.format_mfa(e.module, e.fn_name, e.arity)
      "#{mfa} cannot be stubbed as original module does not export such function"
    end
  end

  use Application

  def start(_, _) do
    children = [Mack.Server]
    Supervisor.start_link(children, name: Mack.Supervisor, strategy: :one_for_one)
  end

  def stub(module, fn_name, func) do
    Server.stub(module, fn_name, func)
    module
  end

  def expect(module, fn_name, func) do
    Server.expect(module, fn_name, func)
    module
  end

  def defmock(module) do
    original_module = Server.original_module(module)
    Mack.Module.replace!(module, original_module)
    Mack.Server.mock(module)

    :ok
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
