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

  ################### Bug demonstration ###################
  # Run with `mix test test/edge_case_test.exs --seed 0`
  # Because it depends on the order of the tests
  describe "failed verification in global mode" do
    # must be in global mode
    setup :set_mimic_global
    # must verify on exit
    setup :verify_on_exit!

    # this test must run first
    test "reports an unmet expectation on exit" do
      # must have expecation remaining
      expect(Calculator, :add, 2, fn x, y -> x + y end)
      assert Calculator.add(1, 2) == 3
    end
  end

  describe "the test after a failed global verification" do
    # this test must run after the previous test
    test "can use Mimic" do
      # this stub fails because the global owner was never cleaned up
      stub(Calculator, :add, fn _, _ -> 0 end)
      assert Calculator.add(1, 2) == 0
    end
  end
end
