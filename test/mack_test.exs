defmodule Mack.Test do
  use ExUnit.Case, async: true
  import Mack

  # setup :verify_on_exit!
  test "no stubs" do
    assert TestModule.add(2, 2) == 4
    assert TestModule.mult(2, 3) == 6
  end

  test "stub" do
    TestModule
    |> stub(:add, fn x, _y -> x + 2 end)
    |> stub(:mult, fn x, _y -> x * 2 end)

    assert TestModule.add(2, :undefined) == 4
    assert TestModule.mult(2, 3) == 4
  end

  test "stub redefining overrides" do
    TestModule
    |> stub(:add, fn x, _y -> x + 2 end)
    |> stub(:add, fn x, _y -> x + 3 end)

    assert TestModule.add(2, :undefined) == 5
  end

  test "expect" do
    TestModule
    |> expect(:add, fn x, _y -> x + 2 end)
    |> expect(:mult, fn x, _y -> x * 2 end)

    assert TestModule.add(4, :_) == 6
    assert TestModule.mult(5, :_) == 10
  end

  test "expecting when no expectation is defined" do
    TestModule
    |> expect(:add, fn x, _y -> x + 2 end)
    |> expect(:mult, fn x, _y -> x * 2 end)

    assert TestModule.add(4, :_) == 6
    assert TestModule.mult(5, :_) == 10
    assert_raise Mack.UnexpectedCallError, fn -> TestModule.mult(5, :_) == 10 end
  end
end
