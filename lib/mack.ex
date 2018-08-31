defmodule Mack do
  alias Mack.Server

  defmodule UnexpectedCallError do
    defexception [:message]
  end

  defmodule VerificationError do
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
    children = [Server]
    Supervisor.start_link(children, name: Mack.Supervisor, strategy: :one_for_one)
  end

  def stub(module, fn_name, func) do
    case Server.stub(module, fn_name, func) do
      :ok -> module
      {:error, :not_mocked} -> raise UnexpectedCallError, "Module #{module} not mocked"
    end
  end

  def expect(module, fn_name, func) do
    case Server.expect(module, fn_name, func) do
      :ok -> module
      {:error, :not_mocked} -> raise UnexpectedCallError, "Module #{module} not mocked"
    end
  end

  def defmock(module) do
    original_module = Server.original_module(module)
    Mack.Module.replace!(module, original_module)
    Server.mock(module)

    :ok
  end

  @doc """
  Verifies the current process after it exits.

  If you want to verify expectations for all tests, you can use
  `verify_on_exit!/1` as a setup callback:

      setup :verify_on_exit!

  """
  def verify_on_exit!(_context \\ %{}) do
    pid = self()

    ExUnit.Callbacks.on_exit(Mack, fn -> verify!(pid) end)
  end

  def verify!(pid \\ self()) do
    pending = Server.verify(pid)

    messages =
      for {module, name, arity} <- pending do
        mfa = Exception.format_mfa(module, name, arity)
        "  * expected #{mfa} to be invoked"
      end

    if messages != [] do
      raise VerificationError,
            "error while verifying mocks for #{inspect(pid)}:\n\n" <> Enum.join(messages, "\n")
    end

    :ok
  end
end
