defmodule Mimic.TestExpect do
  use Mimic.TestCaseWithSomeDefaultStub
  # use ExUnit.Case, async: true
  import Mimic

  describe "expect/3" do
    test "should fail due to expected function not called" do
      expect(Calculator, :add, fn _, _ -> 3 end)
    end
  end
end
