defmodule Mack.Test do
  use ExUnit.Case, async: true
  import Mack

  test "no stubs" do
    assert Calculator.add(2, 2) == 4
    assert Calculator.mult(2, 3) == 6
  end

  describe "stub/3" do
    test "called multiple times" do
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

    test "does not fail verification if not called" do
      stub(Calculator, :add, fn x, y -> x + y end)
      verify!()
    end

    test "respects calls precedence" do
      Calculator
      |> stub(:add, fn x, y -> x + y end)
      |> expect(:add, fn _, _ -> :expected end)

      assert Calculator.add(1, 1) == :expected
      verify!()
    end

    test "allows multiple invocations" do
      stub(Calculator, :add, fn x, y -> x + y end)
      assert Calculator.add(1, 2) == 3
      assert Calculator.add(3, 4) == 7
    end

    test "invokes stub after expectations are fulfilled" do
      Calculator
      |> stub(:add, fn _x, _y -> :stub end)
      |> expect(:add, fn _, _ -> :expected end)
      |> expect(:add, fn _, _ -> :expected end)

      assert Calculator.add(1, 1) == :expected
      assert Calculator.add(1, 1) == :expected
      assert Calculator.add(1, 1) == :stub
      verify!()
    end

    test "stub redefining overrides" do
      Calculator
      |> stub(:add, fn x, _y -> x + 2 end)
      |> stub(:add, fn x, _y -> x + 3 end)

      assert Calculator.add(2, :undefined) == 5
    end
  end

  describe "expect/3" do
    test "basic expectation" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      assert Calculator.add(4, :_) == 6
      assert Calculator.mult(5, :_) == 10
    end

    test "expectation not being fulfilled" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      assert_raise Mack.VerificationError, fn -> verify!(self()) end
    end

    test "expecting when no expectation is defined" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      assert Calculator.add(4, :_) == 6
      assert Calculator.mult(5, :_) == 10
      assert_raise Mack.UnexpectedCallError, fn -> Calculator.mult(5, :_) == 10 end
    end

    test "expecting when mock is not defined" do
      assert_raise Mack.UnexpectedCallError, fn -> expect(Date, :add, fn x, _y -> x + 2 end) end
    end
  end
end
