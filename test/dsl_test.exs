defmodule Mimic.DSLTest do
  use ExUnit.Case, async: false
  use Mimic.DSL

  setup :set_mimic_private

  @stub 10

  test "basic example" do
    stub(Calculator.add(_x, _y), do: @stub)
    expect Calculator.add(x, y), do: x + y
    expect Calculator.add(x, y), do: x + y + 1
    expect Calculator.mult(x, y), do: x * y

    assert Calculator.add(2, 3) == 5
    assert Calculator.mult(2, 3) == 6
    assert Calculator.add(2, 3) == 6

    message =
      ~r"expected Calculator.add/2 to be called 1 time\(s\) but it has been called 2 time\(s\)"

    assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.add(5, 3) end
  end

  test "guards on stub" do
    stub Calculator.add(x, y) when rem(x, 2) == 0 and y == 2 do
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

  test "expect supports optional num_calls" do
    n = 2

    expect Calculator.add(x, y), num_calls: n do
      x + y
    end

    assert Calculator.add(1, 3) == 4
    assert Calculator.add(1, 4) == 5
  end

  test "expect supports optional num_calls with guard clause" do
    expect Calculator.add(x, y) when x == 1, num_calls: 2 do
      x + y
    end

    assert Calculator.add(1, 3) == 4

    assert_raise FunctionClauseError, fn ->
      Calculator.add(2, 4) == 6
    end
  end
end
