defmodule Mimic.TestExpect do
  use Mimic.TestCaseWithSomeDefaultStub
  # using ExUnit.Case will make test failed as expected
  # use ExUnit.Case, async: true
  use Mimic

  describe "expect/3" do
    test "should fail due to expected function not called" do
      expect(Calculator, :add, fn _, _ -> 3 end)
    end
  end
end
