defmodule Mimic.GlobalTeardownTest do
  use ExUnit.Case, async: false

  # Releasing global mode has to be synchronous with the `on_exit` callback
  # `verify_on_exit!` registers, because that callback is the last thing ExUnit
  # waits for before starting the next test. If any part of it is a cast, the
  # next (private mode) test can still observe {:mode, :global, <finished test
  # pid>} and blow up with "Expect cannot be called by the current process."
  #
  # Suspending the Coordinator stands in for "the Coordinator has not been
  # scheduled yet", which is what CPU contention on a busy CI runner produces.

  setup do
    on_exit(fn ->
      :sys.resume(Mimic.Coordinator)
      Mimic.Coordinator.set_private_mode()
    end)
  end

  test "Server.exit/1 does not return before global mode is released" do
    owner = start_global_owner()
    stop(owner)

    # Busy system: the Coordinator does not get scheduled for a while.
    :sys.suspend(Mimic.Coordinator)

    # What `verify_on_exit!`'s on_exit callback does (mimic.ex).
    {teardown, teardown_ref} = spawn_monitor(fn -> Mimic.Server.exit(owner) end)

    refute_receive {:DOWN, ^teardown_ref, :process, ^teardown, _},
                   100,
                   "Server.exit/1 returned while global mode was still set"

    :sys.resume(Mimic.Coordinator)
    assert_receive {:DOWN, ^teardown_ref, :process, ^teardown, :normal}

    assert Mimic.Coordinator.get_mode() == :private
  end

  test "the next test can set expectations once the owner's teardown has run" do
    owner = start_global_owner()
    stop(owner)
    Mimic.Server.exit(owner)

    Mimic.expect(Calculator, :add, fn _, _ -> 42 end)
    assert Calculator.add(1, 2) == 42
  end

  # A global mode test process, set up the way `use Mimic` plus
  # `setup :set_mimic_from_context` set up an `async: false` case.
  defp start_global_owner do
    test_pid = self()

    owner =
      spawn(fn ->
        Mimic.Server.verify_on_exit(self())
        Mimic.set_mimic_global(%{})
        Mimic.stub(Calculator, :add, fn _, _ -> :stubbed end)
        send(test_pid, :ready)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :ready
    assert Mimic.Coordinator.get_mode() == :global

    owner
  end

  defp stop(owner) do
    ref = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^owner, :normal}
  end
end
