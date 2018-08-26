defmodule Mack.Test do
  use ExUnit.Case, async: true
  import Mack

  # setup :verify_on_exit!
  test "no stubs" do
    assert Calculator.add(2, 2) == 4
    assert Calculator.mult(2, 3) == 6
  end

  test "stub" do
    Calculator
    |> stub(:add, fn x, _y -> x + 2 end)
    |> stub(:mult, fn x, _y -> x * 2 end)

    Counter
    |> stub(:inc, fn x -> x + 7 end)
    |> stub(:add, fn counter, x -> counter + x + 7 end)

    assert Calculator.add(2, :undefined) == 4
    assert Calculator.mult(2, 3) == 4
    assert Counter.inc(3) == 10
    assert Counter.add(3, 10) == 20
  end

  test "stub redefining overrides" do
    Calculator
    |> stub(:add, fn x, _y -> x + 2 end)
    |> stub(:add, fn x, _y -> x + 3 end)

    assert Calculator.add(2, :undefined) == 5
  end

  test "expect" do
    Calculator
    |> expect(:add, fn x, _y -> x + 2 end)
    |> expect(:mult, fn x, _y -> x * 2 end)

    assert Calculator.add(4, :_) == 6
    assert Calculator.mult(5, :_) == 10
  end

  test "expecting when no expectation is defined" do
    Calculator
    |> expect(:add, fn x, _y -> x + 2 end)
    |> expect(:mult, fn x, _y -> x * 2 end)

    assert Calculator.add(4, :_) == 6
    assert Calculator.mult(5, :_) == 10
    assert_raise Mack.UnexpectedCallError, fn -> Calculator.mult(5, :_) == 10 end
  end

  test "expecting when no defmock not called" do
    assert_raise Mack.UnexpectedCallError, fn -> expect(Date, :add, fn x, _y -> x + 2 end) end
  end
end
