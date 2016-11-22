defmodule Mack.Test do
  use ExUnit.Case
  import Mack
  doctest Mack

  defmodule TestModule do
    def sum(a, b), do: a + b
  end

  setup_all do
    new(TestModule)
    :ok
  end

  setup do
    on_exit fn -> reset(TestModule) end
    :ok
  end

  describe "new/1" do
    test "has no stubs" do
      assert_raise UndefinedFunctionError, fn -> TestModule.sum(1, 2) end
    end
  end

  describe "allow/4" do
    test "stub a function call with scalar result" do
      allow(TestModule, :sum, [2, 2], 5)

      assert TestModule.sum(2, 2) == 5
    end

    test "stub a function call with _ arg with scalar result" do
      allow(TestModule, :sum, [:_, 2], 5)

      assert TestModule.sum(1, 2) == 5
    end

    test "stub a function call with function result" do
      allow(TestModule, :sum, [2, 2], fn x, y -> {x, y} end)

      assert TestModule.sum(2, 2) == {2, 2}
    end

    test "stub a function call with fn" do
      allow TestModule.sum(2, 3), fn x, y ->
        x * y
      end

      assert TestModule.sum(2, 3) == 6
    end

    # test "stub a function call with do" do
      # allow TestModule.sum(x, y) do
        # x + y
      # end

      # assert TestModule.sum(2, 3) == 6
    # end

    # test "stub a function call with function result throwing an error" do
      # allow(TestModule, :sum, [2, 2], fn x, y -> exit(1) end)

      # assert TestModule.sum(2, 2) == {2, 2}
    # end

    # test "stub a function call with _" do
      # allow TestModule.sum(:_, :_) do

      # end

      # assert TestModule.sum(2, 2) == 5
    # end
  end

  describe "history/1" do
    test "empty list if nothing was called" do
      assert history(TestModule) == []
    end

    test "populated list if something was called" do
      allow(TestModule, :sum, [4, 2], 6)
      allow(TestModule, :sum, [1, 2], 3)
      TestModule.sum(4, 2)
      TestModule.sum(1, 2)
      assert history(TestModule) == [{self, :sum, [1, 2], 3}, {self, :sum, [4, 2], 6}]
    end
  end

  describe "reset/1" do
    test "erases history" do
      allow(TestModule, :sum, [4, 2], 6)
      allow(TestModule, :sum, [1, 2], 3)
      TestModule.sum(4, 2)
      TestModule.sum(1, 2)

      assert history(TestModule) != []
      reset(TestModule)
      assert history(TestModule) == []
    end

    test "erases stubs" do
      allow(TestModule, :sum, [4, 2], 6)
      TestModule.sum(4, 2)

      reset(TestModule)
      assert_raise UndefinedFunctionError, fn -> TestModule.sum(4, 2) end
    end
  end
end
