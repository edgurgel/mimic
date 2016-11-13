defmodule Mimic do
  @moduledoc """
  Mimic is a library that simplifies the usage of mocks.

  Modules need to be prepared so that they can be used.

  You must first call `copy` in your `test_helper.exs` for
  each module that may have the behaviour changed.

  ```
  Mimic.copy(Calculator)

  ExUnit.start()
  ```

  Calling `copy` will not change the behaviour of the module.

  The user must call `stub/3` or `expect/3` so that the functions will
  behave differently.
  """
  alias Mimic.Server

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
    Supervisor.start_link(children, name: Mimic.Supervisor, strategy: :one_for_one)
  end

  @doc """
  To allow `Calculator.add/2` to be called:

    stub(Calculator, :add, fn x, y -> x + y end)

  """
  @spec stub(atom, atom, function) :: module
  def stub(module, fn_name, func) do
    arity = :erlang.fun_info(func)[:arity]
    raise_if_not_mocked!(module)
    raise_if_not_exported_function!(module, fn_name, arity)

    case Server.stub(module, fn_name, arity, func) do
      :ok ->
        module

      {:error, :not_global_owner} ->
        raise ArgumentError,
              "Stub cannot be called by the current process. Only the global owner is allowed."
    end
  end

  def stub(module) do
    raise_if_not_mocked!(module)

    case Server.stub(module) do
      :ok ->
        module

      {:error, :not_global_owner} ->
        raise ArgumentError,
              "Stub cannot be called by the current process. Only the global owner is allowed."
    end
  end

  @doc """
  To expect `Calculator.add/2` to be called:

    expect(Calculator, :add, fn x, y -> x + y end)

  If this function is not called the verification step will raise
  """
  @spec expect(atom, atom, function) :: module
  def expect(module, fn_name, func) do
    arity = :erlang.fun_info(func)[:arity]
    raise_if_not_mocked!(module)
    raise_if_not_exported_function!(module, fn_name, arity)

    case Server.expect(module, fn_name, arity, func) do
      :ok ->
        module

      {:error, :not_global_owner} ->
        raise ArgumentError,
              "Expect cannot be called by the current process. Only the global owner is allowed."
    end
  end

  defp raise_if_not_mocked!(module) do
    unless function_exported?(module, :__mimic_info__, 0) do
      raise ArgumentError, "Module #{inspect(module)} not mocked"
    end
  end

  defp raise_if_not_exported_function!(module, fn_name, arity) do
    unless function_exported?(module, fn_name, arity) do
      raise ArgumentError, "Function #{fn_name}/#{arity} not defined for #{inspect(module)}"
    end
  end

  @doc """
  Allows other processes to share expectations and stubs defined by another process.

  ## Examples
  To allow `other_pid` to call any stubs or expectations defined for `Calculator`:

      allow(Calculator, self(), other_pid)

  """
  def allow(module, owner_pid, allowed_pid) do
    case Server.allow(module, owner_pid, allowed_pid) do
      :ok ->
        module

      {:error, :global_mode} ->
        raise ArgumentError, "Allow must not be called when mode is global."
    end
  end

  @doc """
  Define `module` to be able to mock functions
  """
  @spec copy(atom) :: :ok
  def copy(module) do
    original_module = Mimic.Module.original(module)
    Mimic.Module.replace!(module, original_module)

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

    Server.verify_on_exit(pid)

    ExUnit.Callbacks.on_exit(Mimic, fn ->
      verify!(pid)
      Server.exit(pid)
    end)
  end

  @doc """
  Sets the mode to private. Mocks can be set and user by the process

      setup :set_mimic_private

  """
  def set_mimic_private(_context \\ %{}), do: Server.set_private_mode()

  @doc """
  Sets the mode to global. Mocks can be set and used by all processes

      setup :set_mimic_global

  """
  def set_mimic_global(_context \\ %{}), do: Server.set_global_mode(self())

  @doc """
  Chooses the mode based on ExUnit context. If `async` is `true` then
  the mode is private, otherwise global

      setup :set_mimic_from_context

  """
  def set_mimic_from_context(%{async: true} = _context), do: set_mimic_private()
  def set_mimic_from_context(_context), do: set_mimic_global()

  @doc """
  Verify if expectations were fulfilled for a process `pid`
  """
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
