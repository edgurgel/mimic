defmodule Mack.Test do
  use ExUnit.Case
  import Mack
  doctest Mack

  defmodule TestModule do
    def sum(a, b), do: a + b
  end

  setup_all do
    new TestModule
    :ok
  end

  setup do
    on_exit fn -> reset TestModule end
    :ok
  end

  describe "allow/4" do
    test "stub a function call" do
      allow(TestModule, :sum, [2, 2], 5)
      assert TestModule.sum(2, 2) == 5
    end
  end

  describe "history/1" do
    test "empty list if nothing was called" do
      assert history(TestModule) == []
    end

    test "populated list if something was called" do
      TestModule.sum(4, 2)
      TestModule.div(3, 2)
      assert history(TestModule) == [div: [3, 2], sum: [4, 2]]
    end
  end
end
