defmodule Mack.Test do
  use ExUnit.Case
  import Mack
  require Mack
  doctest Mack

  setup_all do
    new(TestModule)
    on_exit fn -> unload(TestModule) end
    :ok
  end

  setup do
    reset(TestModule)
    :ok
  end

  describe "new/1" do
    test "has no stubs" do
      assert_raise UndefinedFunctionError, fn -> TestModule.sum(1, 2) end
    end

    test "backups original module" do
      assert apply(String.to_atom("Elixir.TestModule_backup_mack"), :sum, [1, 3]) == 4
    end
  end

  describe "unload/1" do
    test "restore original module" do
      unload TestModule
      assert TestModule.sum(100, 200) == 300
      new TestModule
    end
  end

  describe "received?/4" do
    test "expect call" do
      allow(TestModule, :sum, [2, 2], 5)

      assert TestModule.sum(2, 2) == 5
      assert received? TestModule, :sum, [2, 2], 5
      refute received? TestModule, :sum, [4, 4], 5
    end
  end

  describe "allow/4" do
    test "stub a function call with scalar result" do
      allow(TestModule, :sum, [2, 2], 5)

      assert TestModule.sum(2, 2) == 5
    end

    test "stub a function call that does not exist" do
      allow(TestModule, :times, [2, 2], 9)

      assert TestModule.times(2, 2) == 9
    end

    test "stub a function call with timeout" do
      allow(TestModule, :sum, [2, 2], fn _, _ -> :timer.sleep(5001); 4 end)
      allow(TestModule, :sum, [2, 3], 5)

      assert TestModule.sum(2, 2) == 4
      assert TestModule.sum(2, 3) == 5
    end

    test "stub a function call with _ arg with scalar result" do
      allow(TestModule, :sum, [:_, 2], 5)
      allow(TestModule, :sum, [2, :_], 9)

      assert TestModule.sum(1, 2) == 5
      assert TestModule.sum(2, 3) == 9
    end

    test "stub a function call with _ arg with function result" do
      allow(TestModule, :sum, [:_, :_], fn x, y -> {x, y, x + y} end)

      assert TestModule.sum(3, 7) == {3, 7, 10}
    end

    test "stub a function call with function result" do
      allow(TestModule, :sum, [2, 2], fn x, y -> {x, y} end)

      assert TestModule.sum(2, 2) == {2, 2}
    end

    test "stub a function call with do" do
      allow TestModule.sum(x, y) do
        x * y
      end

      assert TestModule.sum(2, 3) == 6
    end

    test "stub a function call with a match and do" do
      allow TestModule.sum(_, 3) do
        5
      end
    end


    test "stub a function call with function result throwing a value" do
      allow(TestModule, :sum, fn _x, _y -> throw(:sum_throw) end)
      assert catch_throw(TestModule.sum(1, 2)) == :sum_throw
    end

    test "stub a function call with function result raising an erlang error" do
      allow(TestModule, :sum, fn _x, _y -> :erlang.error(:sum_error) end)
      assert_raise ErlangError, "erlang error: :sum_error", fn -> TestModule.sum(1, 2) end
    end

    test "stub a function call with function result raising an exception" do
      allow(TestModule, :sum, fn _x, _y -> raise ArgumentError end)
      assert_raise ArgumentError, "argument error", fn -> TestModule.sum(1, 2) end
    end

    test "stub a function call with function result raising an exit" do
      allow(TestModule, :sum, fn _x, _y -> exit(1) end)
      assert catch_exit(TestModule.sum(1, 2)) == 1
    end
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
      assert history(TestModule) == [{self, :sum, [1, 2], {:value, 3}}, {self, :sum, [4, 2], {:value, 6}}]
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
