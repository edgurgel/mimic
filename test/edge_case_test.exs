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
end
