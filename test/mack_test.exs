defmodule Mack.Test do
  use ExUnit.Case, async: true
  import Mack

  # setup :verify_on_exit!

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

  # FIXME
  test "expect" do
    TestModule
    |> expect(:add, fn x, _y -> x + 2 end)
    |> expect(:mult, fn x, _y -> x * 2 end)

    assert TestModule.add(2, 3) == 5
    assert TestModule.mult(2, 3) == 6
  end
end
