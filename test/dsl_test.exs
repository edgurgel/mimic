defmodule Mimic.DSLTest do
  use ExUnit.Case, async: true
  use Mimic.DSL

  test "basic example" do
    allow Calculator.add(_x, _y), do: :stub
    expect Calculator.add(x, y), do: x + y
    expect Calculator.mult(x, y), do: x * y

    assert Calculator.add(2, 3) == 5
    assert Calculator.mult(2, 3) == 6

    assert Calculator.add(2, 3) == :stub
  end

  test "guards on allow" do
    allow Calculator.add(x, y) when rem(x, 2) == 0 and y == 2 do
      x + y
    end

    assert Calculator.add(2, 2) == 4
    assert_raise FunctionClauseError, fn ->
      Calculator.add(3, 1)
    end
  end

  test "guards on expect" do
    expect Calculator.add(x, y) when rem(x, 2) == 0 and y == 2 do
      x + y
    end

    assert_raise FunctionClauseError, fn ->
      Calculator.add(3, 1)
    end
  end
end
