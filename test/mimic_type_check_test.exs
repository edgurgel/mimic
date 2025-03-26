defmodule MimicTypeCheckTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Typecheck.Calculator

  setup :set_mimic_private

  describe "stub/3" do
    test "does not raise with correct type" do
      stub(Calculator, :add, fn _x, _y -> 42 end)

      assert Calculator.add(2, 7) == 42
    end

    test "raises on wrong argument" do
      stub(Calculator, :add, fn _x, _y -> 42 end)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/1st argument value :not_a_number does not match 1st parameter's type number()./,
        fn -> Calculator.add(:not_a_number, 7) end
      )
    end

    test "raises on wrong return value" do
      stub(Calculator, :add, fn _x, _y -> :not_a_number end)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/Returned value :not_a_number does not match type number()/,
        fn -> Calculator.add(77, 7) end
      )
    end
  end

  defmodule InverseCalculator do
    @moduledoc false
    @behaviour AddAdapter
    def add(_x, _y), do: :not_a_number
  end

  describe "stub_with/2" do
    test "raises on wrong argument" do
      stub_with(Calculator, InverseCalculator)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/1st argument value :not_a_number does not match 1st parameter's type number()./,
        fn -> Calculator.add(:not_a_number, 7) end
      )
    end

    test "raises on wrong return value" do
      stub_with(Calculator, InverseCalculator)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/Returned value :not_a_number does not match type number()/,
        fn -> Calculator.add(77, 7) end
      )
    end
  end

  describe "expect/4" do
    test "does not raise with correct type" do
      expect(Calculator, :add, fn _x, _y -> 42 end)

      assert Calculator.add(13, 7) == 42
    end

    test "raises on wrong argument" do
      expect(Calculator, :add, fn _x, _y -> 42 end)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/1st argument value :not_a_number does not match 1st parameter's type number()./,
        fn -> Calculator.add(:not_a_number, 7) end
      )
    end

    test "raises on wrong return value" do
      expect(Calculator, :add, fn _x, _y -> :not_a_number end)

      assert_raise(
        Mimic.TypeCheckError,
        ~r/Returned value :not_a_number does not match type number()/,
        fn -> Calculator.add(77, 7) end
      )
    end
  end
end
