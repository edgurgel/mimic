defmodule Mimic.Test do
  use ExUnit.Case, async: true
  import Mimic

  describe "no stub or expects private mode" do
    setup :set_mimic_private

    test "no stubs calls original" do
      assert Calculator.add(2, 2) == 4
      assert Calculator.mult(2, 3) == 6
    end
  end

  describe "no stub or expects global mode" do
    setup :set_mimic_global

    test "no stubs calls original" do
      assert Calculator.add(2, 2) == 4
      assert Calculator.mult(2, 3) == 6
    end
  end

  describe "default mode" do
    test "private mode is the default mode" do
      Task.async(fn ->
        Mimic.set_mimic_global()
        stub(Calculator, :add, fn _, _ -> :stub end)

        Task.async(fn ->
          assert Calculator.add(3, 7) == :stub
        end)
        |> Task.await()
      end)
      |> Task.await()

      :timer.sleep(500)
      stub(Calculator, :add, fn _, _ -> :private_stub end)
      assert Calculator.add(3, 7) == :private_stub
    end
  end

  describe "stub/1 private mode" do
    setup :set_mimic_private

    test "stubs all defined functions" do
      stub(Calculator)
      assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(3, 7) end
      assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(4, 9) end

      Task.async(fn ->
        assert Calculator.add(3, 7) == 10
        assert Calculator.mult(4, 9) == 36
      end)
      |> Task.await()
    end

    test "stubbing when mock is not defined" do
      assert_raise ArgumentError, fn -> stub(Date) end
    end
  end

  describe "stub/1 global mode" do
    setup :set_mimic_global

    test "stubs all defined functions" do
      stub(Calculator)
      assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(2, 2) end
      assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(2, 2) end

      Task.async(fn ->
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(2, 2) end
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(2, 2) end
      end)
      |> Task.await()
    end

    test "raises if a different process used stub" do
      Task.async(fn ->
        assert_raise ArgumentError,
                     "Stub cannot be called by the current process. Only the global owner is allowed.",
                     fn ->
                       stub(Calculator)
                     end
      end)
      |> Task.await()
    end

    test "stubbing when mock is not defined" do
      assert_raise ArgumentError, fn -> stub(Date) end
    end
  end

  describe "stub/3 private mode" do
    setup :set_mimic_private

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

    test "different processes see different results" do
      Calculator
      |> stub(:add, fn x, _y -> x + 2 end)
      |> stub(:mult, fn x, _y -> x * 2 end)

      assert Calculator.add(2, :undefined) == 4
      assert Calculator.mult(2, 3) == 4

      Task.async(fn ->
        Calculator
        |> stub(:add, fn x, _y -> x + 3 end)
        |> stub(:mult, fn x, _y -> x * 7 end)

        assert Calculator.add(2, :undefined) == 5
        assert Calculator.mult(2, 3) == 14
      end)
      |> Task.await()
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
      |> expect(:add, fn _, _ -> :expected_1 end)
      |> expect(:add, fn _, _ -> :expected_2 end)

      assert Calculator.add(1, 1) == :expected_1
      assert Calculator.add(1, 1) == :expected_2
      assert Calculator.add(1, 1) == :stub
      verify!()
    end

    test "stub redefining overrides" do
      Calculator
      |> stub(:add, fn x, _y -> x + 2 end)
      |> stub(:add, fn x, _y -> x + 3 end)

      assert Calculator.add(2, :undefined) == 5
    end

    test "raises if a non copied module is given" do
      assert_raise ArgumentError,
                   "Module String has not been copied.  See docs for Mimic.copy/1",
                   fn ->
                     stub(String, :split, fn x, y -> x + y end)
                   end
    end

    test "raises if function is not in behaviour" do
      assert_raise ArgumentError, "Function oops/2 not defined for Calculator", fn ->
        stub(Calculator, :oops, fn x, y -> x + y end)
      end

      assert_raise ArgumentError, "Function add/3 not defined for Calculator", fn ->
        stub(Calculator, :add, fn x, y, z -> x + y + z end)
      end
    end
  end

  describe "stub/3 global mode" do
    setup :set_mimic_global

    test "called multiple times" do
      Calculator
      |> stub(:add, fn x, _y -> x + 2 end)
      |> stub(:mult, fn x, _y -> x * 2 end)

      Counter
      |> stub(:inc, fn x -> x + 7 end)
      |> stub(:add, fn counter, x -> counter + x + 7 end)

      Task.async(fn ->
        assert Calculator.add(2, :undefined) == 4
        assert Calculator.mult(2, 3) == 4
        assert Counter.inc(3) == 10
        assert Counter.add(3, 10) == 20
      end)
      |> Task.await()
    end

    test "respects calls precedence" do
      Calculator
      |> stub(:add, fn x, y -> x + y end)
      |> expect(:add, fn _, _ -> :expected end)

      Task.async(fn ->
        assert Calculator.add(1, 1) == :expected
      end)
      |> Task.await()

      verify!()
    end

    test "allows multiple invocations" do
      stub(Calculator, :add, fn x, y -> x + y end)

      Task.async(fn ->
        assert Calculator.add(1, 2) == 3
        assert Calculator.add(3, 4) == 7
      end)
      |> Task.await()
    end

    test "invokes stub after expectations are fulfilled" do
      Calculator
      |> stub(:add, fn _x, _y -> :stub end)
      |> expect(:add, fn _, _ -> :expected end)
      |> expect(:add, fn _, _ -> :expected end)

      Task.async(fn ->
        assert Calculator.add(1, 1) == :expected
        assert Calculator.add(1, 1) == :expected
        assert Calculator.add(1, 1) == :stub
      end)
      |> Task.await()

      verify!()
    end

    test "stub redefining overrides" do
      Calculator
      |> stub(:add, fn x, _y -> x + 2 end)
      |> stub(:add, fn x, _y -> x + 3 end)

      Task.async(fn ->
        assert Calculator.add(2, :undefined) == 5
      end)
      |> Task.await()
    end

    test "raises if a different process used stub" do
      Task.async(fn ->
        assert_raise ArgumentError,
                     "Stub cannot be called by the current process. Only the global owner is allowed.",
                     fn ->
                       stub(Calculator, :add, fn x, y -> x + y end)
                     end
      end)
      |> Task.await()
    end

    test "raises if a non copied module is given" do
      assert_raise ArgumentError,
                   "Module String has not been copied.  See docs for Mimic.copy/1",
                   fn ->
                     stub(String, :split, fn x, y -> x + y end)
                   end
    end

    test "raises if function is not defined" do
      assert_raise ArgumentError, "Function oops/2 not defined for Calculator", fn ->
        stub(Calculator, :oops, fn x, y -> x + y end)
      end

      assert_raise ArgumentError, "Function add/3 not defined for Calculator", fn ->
        stub(Calculator, :add, fn x, y, z -> x + y + z end)
      end
    end
  end

  describe "expect/4 private mode" do
    setup :set_mimic_private

    test "basic expectation" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      assert Calculator.add(4, :_) == 6
      assert Calculator.mult(5, :_) == 10
    end

    test "stacking expectations" do
      Calculator
      |> expect(:add, fn _x, _y -> :first end)
      |> expect(:add, fn _x, _y -> :second end)

      assert Calculator.add(4, :_) == :first
      assert Calculator.add(5, :_) == :second
    end

    test "expect multiple calls" do
      Calculator
      |> expect(:add, 2, fn x, y -> {:add, x, y} end)

      assert Calculator.add(4, 3) == {:add, 4, 3}
      assert Calculator.add(5, 2) == {:add, 5, 2}
    end

    test "expectation not being fulfilled" do
      Calculator
      |> expect(:add, 2, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      message =
        ~r"\* expected Calculator.mult/2 to be invoked 1 time\(s\) but it has been called 0 time\(s\)"

      assert_raise Mimic.VerificationError, message, fn -> verify!(self()) end

      message =
        ~r"\* expected Calculator.add/2 to be invoked 2 time\(s\) but it has been called 0 time\(s\)"

      assert_raise Mimic.VerificationError, message, fn -> verify!(self()) end

      Calculator.add(1, 2)
      Calculator.add(2, 3)
      Calculator.mult(4, 5)
      verify!(self())
    end

    test "expecting when no expectation is defined calls original" do
      Calculator
      |> expect(:add, fn x, _y -> {:mock, x + 2} end)
      |> expect(:mult, fn x, _y -> {:mock, x * 2} end)

      assert Calculator.add(4, :_) == {:mock, 6}
      assert Calculator.mult(5, :_) == {:mock, 10}

      assert Calculator.mult(5, 3) == 15
    end

    test "raises if a non copied module is given" do
      assert_raise ArgumentError,
                   "Module String has not been copied.  See docs for Mimic.copy/1",
                   fn ->
                     expect(String, :split, fn x, y -> x + y end)
                   end
    end

    test "expecting when mock is not defined" do
      assert_raise ArgumentError, fn -> expect(Date, :add, fn x, _y -> x + 2 end) end
    end

    test "expecting 0 calls should point to reject" do
      message = ~r"Expecting 0 calls should be done through Mimic.reject/1"

      assert_raise ArgumentError, message, fn ->
        expect(Calculator, :add, 0, fn x, y -> x + y end)
      end
    end
  end

  describe "expect/4 global mode" do
    setup :set_mimic_global

    test "basic expectation" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      Task.async(fn ->
        assert Calculator.add(4, :_) == 6
        assert Calculator.mult(5, :_) == 10
      end)
      |> Task.await()
    end

    test "stacking expectations" do
      Calculator
      |> expect(:add, fn _x, _y -> :first end)
      |> expect(:add, fn _x, _y -> :second end)

      Task.async(fn ->
        assert Calculator.add(4, :_) == :first
        assert Calculator.add(5, :_) == :second
      end)
      |> Task.await()
    end

    test "expect multiple calls" do
      Calculator
      |> expect(:add, 2, fn x, y -> {:add, x, y} end)

      Task.async(fn ->
        assert Calculator.add(4, 3) == {:add, 4, 3}
        assert Calculator.add(5, 2) == {:add, 5, 2}
      end)
      |> Task.await()
    end

    test "expectation not being fulfilled" do
      Calculator
      |> expect(:add, 2, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      message =
        ~r"\* expected Calculator.mult/2 to be invoked 1 time\(s\) but it has been called 0 time\(s\)"

      assert_raise Mimic.VerificationError, message, fn -> verify!(self()) end

      message =
        ~r"\* expected Calculator.add/2 to be invoked 2 time\(s\) but it has been called 0 time\(s\)"

      assert_raise Mimic.VerificationError, message, fn -> verify!(self()) end

      Task.async(fn ->
        Calculator.add(1, 2)
        Calculator.add(2, 3)
        Calculator.mult(4, 5)
      end)
      |> Task.await()

      verify!(self())
    end

    test "expecting when no expectation is defined calls original" do
      Calculator
      |> expect(:add, fn x, _y -> {:mock, x + 2} end)
      |> expect(:mult, fn x, _y -> {:mock, x * 2} end)

      Task.async(fn ->
        assert Calculator.add(4, :_) == {:mock, 6}
        assert Calculator.mult(5, :_) == {:mock, 10}

        assert Calculator.mult(5, 3) == 15
      end)
      |> Task.await()
    end

    test "raises if a different process used expect" do
      Task.async(fn ->
        assert_raise ArgumentError,
                     "Expect cannot be called by the current process. Only the global owner is allowed.",
                     fn ->
                       expect(Calculator, :add, fn x, y -> x + y end)
                     end
      end)
      |> Task.await()
    end

    test "raises if a non copied module is given" do
      assert_raise ArgumentError,
                   "Module String has not been copied.  See docs for Mimic.copy/1",
                   fn ->
                     expect(String, :split, fn x, y -> x + y end)
                   end
    end

    test "expecting when mock is not defined" do
      assert_raise ArgumentError, fn -> expect(Date, :add, fn x, y -> x + y end) end
    end
  end

  describe "reject/1 private mode" do
    setup :set_mimic_private

    test "expect no call to function" do
      reject(&Calculator.add/2)
      reject(&Calculator.mult/2)

      message =
        ~r"expected Calculator.add/2 to be called 0 time\(s\) but it has been called 1 time\(s\)"

      assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.add(3, 7) end

      message =
        ~r"expected Calculator.mult/2 to be called 0 time\(s\) but it has been called 1 time\(s\)"

      assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.mult(3, 7) end
    end

    test "expectation being fulfilled" do
      reject(&Calculator.add/2)
      reject(&Calculator.mult/2)

      verify!(self())
    end

    test "raises if a non copied module is given" do
      assert_raise ArgumentError,
                   "Module String has not been copied.  See docs for Mimic.copy/1",
                   fn ->
                     reject(String, :split, fn x, y -> x + y end)
                   end
    end

    test "expecting when mock is not defined" do
      assert_raise ArgumentError, fn -> reject(&Date.add/2) end
    end
  end

  describe "reject/1 global mode" do
    setup :set_mimic_global

    test "basic expectation" do
      reject(&Calculator.add/2)
      reject(&Calculator.mult/2)

      Task.async(fn ->
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(4, :_) end
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(4, :_) end
      end)
      |> Task.await()
    end

    test "raises if a different process used expect" do
      Task.async(fn ->
        assert_raise ArgumentError,
                     "Reject cannot be called by the current process. Only the global owner is allowed.",
                     fn ->
                       reject(&Calculator.add/2)
                     end
      end)
      |> Task.await()
    end

    test "expecting when mock is not defined" do
      assert_raise ArgumentError, fn -> reject(&Date.add/2) end
    end
  end

  describe "reject3/ private mode" do
    setup :set_mimic_private

    test "expect no call to function" do
      reject(Calculator, :add, 2)
      reject(Calculator, :mult, 2)

      message =
        ~r"expected Calculator.add/2 to be called 0 time\(s\) but it has been called 1 time\(s\)"

      assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.add(3, 7) end

      message =
        ~r"expected Calculator.mult/2 to be called 0 time\(s\) but it has been called 1 time\(s\)"

      assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.mult(3, 7) end
    end

    test "expectation being fulfilled" do
      reject(Calculator, :add, 2)
      reject(Calculator, :mult, 2)

      verify!(self())
    end

    test "raises if a non copied module is given" do
      assert_raise ArgumentError,
                   "Module String has not been copied.  See docs for Mimic.copy/1",
                   fn ->
                     reject(String, :split, fn x, y -> x + y end)
                   end
    end

    test "expecting when mock is not defined" do
      assert_raise ArgumentError, fn -> reject(Date, :add, 2) end
    end
  end

  describe "reject/3 global mode" do
    setup :set_mimic_global

    test "basic expectation" do
      reject(Calculator, :add, 2)
      reject(Calculator, :mult, 2)

      Task.async(fn ->
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(4, :_) end
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(4, :_) end
      end)
      |> Task.await()
    end

    test "raises if a different process used expect" do
      Task.async(fn ->
        assert_raise ArgumentError,
                     "Reject cannot be called by the current process. Only the global owner is allowed.",
                     fn ->
                       reject(Calculator, :add, 2)
                     end
      end)
      |> Task.await()
    end

    test "expecting when mock is not defined" do
      assert_raise ArgumentError, fn -> reject(Date, :add, 2) end
    end
  end

  describe "allow/3" do
    setup :set_mimic_private
    setup :verify_on_exit!

    test "allows different processes to share mocks from parent process" do
      parent_pid = self()

      {:ok, child_pid} =
        Task.start_link(fn ->
          receive do
            :call_mock ->
              add_result = Calculator.add(1, 1)
              mult_result = Calculator.mult(1, 1)
              send(parent_pid, {:verify, add_result, mult_result})
          end
        end)

      Calculator
      |> expect(:add, fn _, _ -> :expected end)
      |> stub(:mult, fn _, _ -> :stubbed end)
      |> allow(self(), child_pid)

      send(child_pid, :call_mock)

      assert_receive {:verify, add_result, mult_result}
      assert add_result == :expected
      assert mult_result == :stubbed
    end

    test "allows different processes to share mocks from child process" do
      parent_pid = self()

      Calculator
      |> expect(:add, fn _, _ -> :expected end)
      |> stub(:mult, fn _, _ -> :stubbed end)

      Task.async(fn ->
        Calculator
        |> allow(parent_pid, self())

        assert Calculator.add(1, 1) == :expected
        assert Calculator.mult(1, 1) == :stubbed
      end)
      |> Task.await()
    end

    test "allowances are transitive" do
      parent_pid = self()

      {:ok, child_pid} =
        Task.start_link(fn ->
          receive do
            :call_mock ->
              add_result = Calculator.add(1, 1)
              mult_result = Calculator.mult(1, 1)
              send(parent_pid, {:verify, add_result, mult_result})
          end
        end)

      {:ok, transitive_pid} =
        Task.start_link(fn ->
          receive do
            :allow_mock ->
              Calculator
              |> allow(self(), child_pid)

              send(child_pid, :call_mock)
          end
        end)

      Calculator
      |> expect(:add, fn _, _ -> :expected end)
      |> stub(:mult, fn _, _ -> :stubbed end)
      |> allow(self(), transitive_pid)

      send(transitive_pid, :allow_mock)

      receive do
        {:verify, add_result, mult_result} ->
          assert add_result == :expected
          assert mult_result == :stubbed
          verify!()
      after
        1000 -> verify!()
      end
    end

    test "allowances are reclaimed if the owner process dies" do
      parent_pid = self()

      task =
        Task.async(fn ->
          Calculator
          |> expect(:add, fn _, _ -> :expected end)
          |> stub(:mult, fn _, _ -> :stubbed end)
          |> allow(self(), parent_pid)
        end)

      Task.await(task)

      assert Calculator.add(1, 3) == 4

      Calculator
      |> expect(:add, fn x, y -> x + y + 7 end)

      assert Calculator.add(1, 1) == 9
    end

    test "raises if you try to allow process while in global mode" do
      set_mimic_global()
      {:ok, child_pid} = Task.start_link(fn -> Process.sleep(:infinity) end)

      Task.async(fn ->
        assert_raise ArgumentError, "Allow must not be called when mode is global.", fn ->
          Calculator
          |> allow(self(), child_pid)
        end
      end)
      |> Task.await()
    end
  end

  describe "behaviours" do
    test "copies behaviour attributes" do
      behaviours =
        Calculator.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert AddAdapter in behaviours
      assert MultAdapter in behaviours
    end
  end
end
