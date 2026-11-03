defmodule Mimic.EdgeCase do
  use ExUnit.Case
  import Mimic

  describe "auto verification" do
    test "should verify_on_exit! correctly even when stub is called before (simulation test)" do
      set_mimic_private()
      parent_pid = self()

      spawn_link(fn ->
        stub(Calculator, :add, fn _, _ -> 3 end)
        Mimic.Server.verify_on_exit(self())
        expect(Calculator, :add, fn _, _ -> 3 end)
        send(parent_pid, {:ok, self()})
      end)

      assert_receive({:ok, child_pid})

      assert_raise Mimic.VerificationError, fn ->
        verify!(child_pid)
      end
    end
  end

  describe "asynchronous expectation failures" do
    setup :set_mimic_private

    test "reports an assertion raised in a supervised task during explicit verification" do
      supervisor = start_supervised!(Task.Supervisor)

      expect(Calculator, :add, fn _, _ ->
        assert false, "detached task failure"
      end)

      {:ok, task_pid} = Task.Supervisor.start_child(supervisor, fn -> Calculator.add(1, 2) end)
      ref = Process.monitor(task_pid)

      assert_receive {:DOWN, ^ref, :process, ^task_pid, {%ExUnit.AssertionError{}, _stacktrace}}

      assert_raise ExUnit.AssertionError, ~r/detached task failure/, fn ->
        verify!()
      end
    end

    test "successful supervised task calls still pass on-exit verification" do
      verify_on_exit!()
      supervisor = start_supervised!(Task.Supervisor)

      expect(Calculator, :add, fn x, y -> x + y end)

      parent = self()

      {:ok, task_pid} =
        Task.Supervisor.start_child(supervisor, fn ->
          send(parent, {:result, Calculator.add(1, 2)})
        end)

      ref = Process.monitor(task_pid)

      assert_receive {:result, 3}
      assert_receive {:DOWN, ^ref, :process, ^task_pid, :normal}
    end

    test "reports an assertion raised in a generic allowed process" do
      expect(Calculator, :add, fn _, _ ->
        assert false, "allowed process failure"
      end)

      child_pid =
        spawn(fn ->
          receive do
            :call -> Calculator.add(1, 2)
          end
        end)

      Calculator |> allow(self(), child_pid)

      ref = Process.monitor(child_pid)
      send(child_pid, :call)

      assert_receive {:DOWN, ^ref, :process, ^child_pid, {%ExUnit.AssertionError{}, _stacktrace}}

      assert_raise ExUnit.AssertionError, ~r/allowed process failure/, fn ->
        verify!()
      end
    end

    test "owner cleanup clears recorded assertion failures" do
      expect(Calculator, :add, fn _, _ ->
        assert false, "failure before cleanup"
      end)

      child_pid =
        spawn(fn ->
          receive do
            :call -> Calculator.add(1, 2)
          end
        end)

      Calculator |> allow(self(), child_pid)

      ref = Process.monitor(child_pid)
      send(child_pid, :call)
      assert_receive {:DOWN, ^ref, :process, ^child_pid, {%ExUnit.AssertionError{}, _stacktrace}}

      Mimic.Server.exit(self())

      expect(Calculator, :add, fn x, y -> x + y end)
      assert Calculator.add(1, 2) == 3
      assert verify!() == :ok
    end

    test "an assertion raised by the expectation owner propagates only once" do
      expect(Calculator, :add, fn _, _ ->
        assert false, "owner process failure"
      end)

      assert_raise ExUnit.AssertionError, ~r/owner process failure/, fn ->
        Calculator.add(1, 2)
      end

      assert verify!() == :ok
    end
  end
end
