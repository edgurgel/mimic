defmodule Mimic.GlobalTeardownRaceTest do
  use ExUnit.Case, async: false

  # Global mode is released asynchronously: the owning process exiting triggers
  # a cast to a Mimic.Server shard, which in turn casts
  # `Coordinator.clear_global_owner/1`. Nothing ExUnit waits on closes that gap, so
  # the next (private mode) test can still observe {:mode, :global, <dead pid>}.
  #
  # Suspending the Coordinator here stands in for "the Coordinator has not been
  # scheduled yet", which is what CPU contention on a busy CI runner produces.

  setup do
    on_exit(fn ->
      :sys.resume(Mimic.Coordinator)
      Mimic.Coordinator.set_private_mode()
    end)
  end

  test "mode is back to private once the global owner's teardown has run" do
    tear_down_global_owner()

    assert Mimic.Coordinator.get_mode() == :private
  end

  test "the next test can set expectations once the global owner's teardown has run" do
    tear_down_global_owner()

    Mimic.expect(Calculator, :add, fn _, _ -> 42 end)
    assert Calculator.add(1, 2) == 42
  end

  # Runs a global mode owner, doing everything ExUnit and Mimic
  # and returns once no further teardown work is synchronised with the test suite.
  defp tear_down_global_owner do
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

    # suspended to "mimic" a busy system
    :sys.suspend(Mimic.Coordinator)

    ref = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^owner, :normal}

    # What Mimic's own `verify_on_exit!` on_exit callback does.
    # ExUnit waits for that callback to return before starting the next test.
    Mimic.Server.exit(owner)

    # Make sure the shard's mailbox is empty: once this call is answered the shard has
    # handled {:exit, owner} and has already cast `clear_global_owner/1`.
    assert Mimic.Server.verify(owner) == []
  end
end
