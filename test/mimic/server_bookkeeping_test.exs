defmodule Mimic.ServerBookkeepingTest do
  use ExUnit.Case, async: false
  # No `use Mimic` and no verify_on_exit! here: these tests assert on the
  # Server's own monitor/verify_on_exit bookkeeping, so they must control
  # exactly which owners get registered.

  setup :set_private_mode

  defp set_private_mode(_context) do
    Mimic.set_mimic_private()
  end

  defp shard(pid) do
    GenServer.whereis({:via, PartitionSupervisor, {Mimic.Server.Partitions, pid}})
  end

  defp state_for(pid), do: :sys.get_state(shard(pid))

  defp monitors_on(pid) do
    {:monitors, monitors} = Process.info(shard(pid), :monitors)
    Enum.count(monitors, &(&1 == {:process, pid}))
  end

  describe "owner monitors" do
    test "repeated stubs and expects from one owner take a single monitor" do
      test_pid = self()

      owner =
        spawn(fn ->
          for _ <- 1..10 do
            Mimic.stub(Calculator, :add, fn x, y -> x + y end)
            Mimic.expect(Calculator, :mult, fn x, y -> x * y end)
          end

          send(test_pid, :registered)
          receive do: (:stop -> :ok)
        end)

      assert_receive :registered

      assert monitors_on(owner) == 1
      assert owner in state_for(owner).monitored

      send(owner, :stop)
    end

    test "the monitor is forgotten when the owner goes down" do
      test_pid = self()

      owner =
        spawn(fn ->
          Mimic.stub(Calculator, :add, fn x, y -> x + y end)
          send(test_pid, :registered)
          receive do: (:stop -> :ok)
        end)

      assert_receive :registered
      assert owner in state_for(owner).monitored

      ref = Process.monitor(owner)
      send(owner, :stop)
      assert_receive {:DOWN, ^ref, :process, ^owner, _}

      state = state_for(owner)
      refute owner in state.monitored
      refute Map.has_key?(state.stubs, owner)
    end
  end

  describe "verify_on_exit bookkeeping" do
    test "Server.exit/1 clears the verify_on_exit flag along with the data" do
      owner = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(owner, :kill) end)

      :ok = Mimic.Server.verify_on_exit(owner)
      assert owner in state_for(owner).verify_on_exit

      Mimic.Server.exit(owner)

      # exit/1 is a cast, but a subsequent call from this process is ordered behind it.
      refute owner in state_for(owner).verify_on_exit
    end

    test "an owner registered for verify_on_exit keeps its data until Server.exit/1" do
      test_pid = self()

      owner =
        spawn(fn ->
          :ok = Mimic.Server.verify_on_exit(self())
          Mimic.expect(Calculator, :add, fn x, y -> x + y end)
          send(test_pid, :registered)
        end)

      assert_receive :registered
      ref = Process.monitor(owner)
      assert_receive {:DOWN, ^ref, :process, ^owner, _}

      # Still verifiable after death: this is what verify_on_exit!/1's callback relies on.
      assert [{{Calculator, :add, 2}, 1, 0}] = Mimic.Server.verify(owner)
      assert owner in state_for(owner).verify_on_exit

      Mimic.Server.exit(owner)

      state = state_for(owner)
      refute owner in state.verify_on_exit
      refute Map.has_key?(state.expectations, owner)
    end
  end
end
