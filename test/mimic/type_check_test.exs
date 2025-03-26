defmodule Mimic.TypeCheckTest do
  use ExUnit.Case, async: true
  alias Mimic.TypeCheck

  setup do
    # Force mimic to copy the module
    Mimic.stub(Typecheck.Calculator, :add, fn _x, _y -> 1 end)
    Mimic.stub(Typecheck.Counter, :inc, fn _x -> 1 end)
    :ok
  end

  describe "wrap/3" do
    test "behaviour typespec return value" do
      func = fn _x, _y -> :not_a_number end
      func = TypeCheck.wrap(Typecheck.Calculator, :add, func)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/Returned value :not_a_number does not match type number()/,
        fn -> func.(1, 2) end
      )
    end

    test "function typespec return value" do
      func = fn _x -> :not_a_number end
      func = TypeCheck.wrap(Typecheck.Counter, :inc, func)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/Returned value :not_a_number does not match type number()/,
        fn -> func.(1) end
      )
    end

    test "function typespec overriding behaviour spec return value" do
      func = fn _x, _y -> :not_a_number end
      func = TypeCheck.wrap(Typecheck.Calculator, :mult, func)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/Returned value :not_a_number does not match type number()/,
        fn -> func.(1, 2) end
      )
    end

    test "behaviour typespec argument" do
      func = fn _x, _y -> 42 end
      func = TypeCheck.wrap(Typecheck.Calculator, :add, func)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/1st argument value :not_a_number does not match 1st parameter's type number()/,
        fn -> func.(:not_a_number, 2) end
      )
    end

    test "function typespec argument" do
      func = fn _x -> 1 end
      func = TypeCheck.wrap(Typecheck.Counter, :inc, func)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/1st argument value :not_a_number does not match 1st parameter's type number()/,
        fn -> func.(:not_a_number) end
      )
    end

    test "function typespec overriding behaviour spec argument" do
      func = fn _x, _y -> 42 end
      func = TypeCheck.wrap(Typecheck.Calculator, :mult, func)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/1st argument value :not_a_number does not match 1st parameter's type number()/,
        fn -> func.(:not_a_number, 2) end
      )
    end
  end
end
