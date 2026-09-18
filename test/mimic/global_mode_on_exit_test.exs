defmodule Mimic.GlobalModeOnExitTest do
  use ExUnit.Case, async: false
  # Nothing here uses `use Mimic`, so each `describe` controls exactly which Mimic
  # callbacks are in play.

  describe "release without verify_on_exit!" do
    # No verify_on_exit! anywhere, so set_mimic_global/1's own callback is the only
    # thing that can release the mode.
    setup do
      on_exit(fn ->
        assert Mimic.Coordinator.get_mode() == :private,
               "set_mimic_global/1 must release global mode in its own on_exit"
      end)

      :ok
    end

    setup do
      Mimic.set_mimic_global(%{})
      :ok
    end

    test "without a stub" do
      assert Mimic.Coordinator.get_mode() == :global
    end

    test "when the owner did arrange something" do
      Mimic.stub(Calculator, :add, fn _, _ -> 42 end)
      assert Calculator.add(1, 2) == 42
      assert Mimic.Coordinator.get_mode() == :global
    end
  end

  describe "callback isolation" do
    setup do
      test_pid = self()

      on_exit(fn ->
        assert Mimic.Coordinator.get_mode() == :private,
               "set_mimic_global/1's callback did not run"

        assert Mimic.Server.verify(test_pid) == []

        assert :ets.lookup(Mimic.Coordinator, {test_pid, Calculator}) == [],
               "verify_on_exit!/1's callback did not run: Server.exit/1 never cleared the owner"
      end)

      :ok
    end

    setup do
      Mimic.verify_on_exit!()
      Mimic.set_mimic_global(%{})
      :ok
    end

    test "both of Mimic's on_exit callbacks survive each other" do
      Mimic.stub(Calculator, :add, fn _, _ -> 42 end)

      assert :ets.lookup(Mimic.Coordinator, {self(), Calculator}) != []
      assert Calculator.add(1, 2) == 42
    end
  end

  describe "outside a test process" do
    test "set_mimic_global/1 raises" do
      test_pid = self()

      spawn(fn ->
        result =
          try do
            Mimic.set_mimic_global(%{})
          rescue
            e in RuntimeError -> {:raised, e.message}
          end

        send(test_pid, {:result, result})
      end)

      assert_receive {:result, {:raised, message}}, 2_000
      assert message =~ "cannot be set to global mode outside of a test process"

      # It raises before taking the mode, so there is nothing to clean up here.
      assert Mimic.Coordinator.get_mode() == :private
    end
  end

  describe "release_global_owner/1" do
    test "releasing an owner that no longer holds global mode leaves it alone" do
      other = spawn(fn -> Process.sleep(:infinity) end)

      on_exit(fn ->
        Process.exit(other, :kill)
        Mimic.Coordinator.set_private_mode()
      end)

      :ok = Mimic.Coordinator.set_global_mode(other)
      assert Mimic.Coordinator.get_mode() == :global

      # Not the owner: must be a no-op.
      :ok = Mimic.Coordinator.release_global_owner(self())
      assert Mimic.Coordinator.get_mode() == :global

      # The owner: releases.
      :ok = Mimic.Coordinator.release_global_owner(other)
      assert Mimic.Coordinator.get_mode() == :private
    end
  end
end
