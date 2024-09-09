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
      parent_pid = self()

      spawn_link(fn ->
        Mimic.set_mimic_global()
        stub(Calculator, :add, fn _, _ -> :stub end)

        child_pid = self()

        spawn_link(fn ->
          assert Calculator.add(3, 7) == :stub

          send(child_pid, :ok_child)
        end)

        assert_receive :ok_child
        send(parent_pid, :ok)
      end)

      assert_receive :ok

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

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(3, 7) == 10
        assert Calculator.mult(4, 9) == 36
        send(parent_pid, :ok)
      end)

      assert_receive :ok
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

      parent_pid = self()

      spawn_link(fn ->
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(2, 2) end
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(2, 2) end
        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "raises if a different process used stub" do
      parent_pid = self()

      spawn_link(fn ->
        assert_raise ArgumentError,
                     "Stub cannot be called by the current process. Only the global owner is allowed.",
                     fn ->
                       stub(Calculator)
                     end

        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "stubbing when mock is not defined" do
      assert_raise ArgumentError, fn -> stub(Date) end
    end
  end

  describe "stub_with/2 private mode" do
    setup :set_mimic_private

    test "called multiple times" do
      stub_with(Calculator, InverseCalculator)

      assert Calculator.add(2, 3) == -1
      assert Calculator.add(3, 2) == 1
    end

    test "stubs all functions which are not in mocking module" do
      stub_with(Calculator, InverseCalculator)

      assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(4, 9) end
    end

    test "undefined mocking module" do
      assert_raise ArgumentError,
                   "Module MissingModule not defined",
                   fn ->
                     stub_with(Calculator, MissingModule)
                   end
    end

    test "undefined mocked module" do
      assert_raise ArgumentError,
                   "Module MissingModule has not been copied. See docs for Mimic.copy/1",
                   fn ->
                     stub_with(MissingModule, InverseCalculator)
                   end
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

      parent_pid = self()

      spawn_link(fn ->
        Calculator
        |> stub(:add, fn x, _y -> x + 3 end)
        |> stub(:mult, fn x, _y -> x * 7 end)

        assert Calculator.add(2, :undefined) == 5
        assert Calculator.mult(2, 3) == 14
        send(parent_pid, :ok)
      end)

      assert_receive :ok
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
                   "Module NotCopiedModule has not been copied. See docs for Mimic.copy/1",
                   fn ->
                     stub(NotCopiedModule, :inc, fn x -> x - 1 end)
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

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(2, :undefined) == 4
        assert Calculator.mult(2, 3) == 4
        assert Counter.inc(3) == 10
        assert Counter.add(3, 10) == 20

        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "respects calls precedence" do
      Calculator
      |> stub(:add, fn x, y -> x + y end)
      |> expect(:add, fn _, _ -> :expected end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(1, 1) == :expected

        send(parent_pid, :ok)
      end)

      assert_receive :ok
      verify!()
    end

    test "allows multiple invocations" do
      stub(Calculator, :add, fn x, y -> x + y end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(1, 2) == 3
        assert Calculator.add(3, 4) == 7
        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "invokes stub after expectations are fulfilled" do
      Calculator
      |> stub(:add, fn _x, _y -> :stub end)
      |> expect(:add, fn _, _ -> :expected end)
      |> expect(:add, fn _, _ -> :expected end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(1, 1) == :expected
        assert Calculator.add(1, 1) == :expected
        assert Calculator.add(1, 1) == :stub

        send(parent_pid, :ok)
      end)

      assert_receive :ok
      verify!()
    end

    test "stub redefining overrides" do
      Calculator
      |> stub(:add, fn x, _y -> x + 2 end)
      |> stub(:add, fn x, _y -> x + 3 end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(2, :undefined) == 5

        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "raises if a different process used stub" do
      parent_pid = self()

      spawn_link(fn ->
        assert_raise ArgumentError,
                     "Stub cannot be called by the current process. Only the global owner is allowed.",
                     fn ->
                       stub(Calculator, :add, fn x, y -> x + y end)
                     end

        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "raises if a non copied module is given" do
      assert_raise ArgumentError,
                   "Module NotCopiedModule has not been copied. See docs for Mimic.copy/1",
                   fn ->
                     stub(NotCopiedModule, :inc, fn x -> x - 1 end)
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
                   "Module NotCopiedModule has not been copied. See docs for Mimic.copy/1",
                   fn ->
                     stub(NotCopiedModule, :inc, fn x -> x - 1 end)
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

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(4, :_) == 6
        assert Calculator.mult(5, :_) == 10

        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "stacking expectations" do
      Calculator
      |> expect(:add, fn _x, _y -> :first end)
      |> expect(:add, fn _x, _y -> :second end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(4, :_) == :first
        assert Calculator.add(5, :_) == :second

        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "expect multiple calls" do
      Calculator
      |> expect(:add, 2, fn x, y -> {:add, x, y} end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(4, 3) == {:add, 4, 3}
        assert Calculator.add(5, 2) == {:add, 5, 2}

        send(parent_pid, :ok)
      end)

      assert_receive :ok
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

      parent_pid = self()

      spawn_link(fn ->
        Calculator.add(1, 2)
        Calculator.add(2, 3)
        Calculator.mult(4, 5)

        send(parent_pid, :ok)
      end)

      assert_receive :ok
      verify!(self())
    end

    test "expecting when no expectation is defined calls original" do
      Calculator
      |> expect(:add, fn x, _y -> {:mock, x + 2} end)
      |> expect(:mult, fn x, _y -> {:mock, x * 2} end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(4, :_) == {:mock, 6}
        assert Calculator.mult(5, :_) == {:mock, 10}

        assert Calculator.mult(5, 3) == 15

        send(parent_pid, :ok)
      end)

      assert_receive :ok
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
                   "Module NotCopiedModule has not been copied. See docs for Mimic.copy/1",
                   fn ->
                     stub(NotCopiedModule, :inc, fn x -> x - 1 end)
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
                   "Module NotCopiedModule has not been copied. See docs for Mimic.copy/1",
                   fn ->
                     stub(NotCopiedModule, :inc, fn x -> x - 1 end)
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

      parent_pid = self()

      spawn_link(fn ->
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(4, :_) end
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(4, :_) end

        send(parent_pid, :ok)
      end)

      assert_receive :ok
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

  describe "reject/3 private mode" do
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
                   "Module NotCopiedModule has not been copied. See docs for Mimic.copy/1",
                   fn ->
                     stub(NotCopiedModule, :inc, fn x -> x - 1 end)
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

      parent_pid = self()

      spawn_link(fn ->
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.add(4, :_) end
        assert_raise Mimic.UnexpectedCallError, fn -> Calculator.mult(4, :_) end

        send(parent_pid, :ok)
      end)

      assert_receive :ok
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

    test "uses $callers property from Task to allow" do
      Calculator
      |> expect(:add, 2, fn x, y -> x + y end)
      |> expect(:mult, fn x, y -> x * y end)
      |> expect(:add, fn _, _ -> 0 end)

      task =
        Task.async(fn ->
          assert Calculator.add(2, 3) == 5
          assert Calculator.add(3, 2) == 5
        end)

      Task.await(task)

      assert Calculator.add(:whatever, :whatever) == 0
      assert Calculator.mult(3, 2) == 6
    end

    test "nested callers are allowed as well" do
      Calculator
      |> expect(:add, 2, fn x, y -> x + y end)
      |> expect(:mult, fn x, y -> x * y end)
      |> expect(:add, fn _, _ -> 0 end)

      task =
        Task.async(fn ->
          assert Calculator.add(2, 3) == 5
          assert Calculator.add(3, 2) == 5

          inner_task =
            Task.async(fn ->
              assert Calculator.add(:whatever, :whatever) == 0
              assert Calculator.mult(3, 2) == 6
            end)

          Task.await(inner_task)
        end)

      Task.await(task)
    end

    test "allows different processes to share mocks from parent process" do
      parent_pid = self()

      child_pid =
        spawn_link(fn ->
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

      spawn_link(fn ->
        Calculator
        |> allow(parent_pid, self())

        assert Calculator.add(1, 1) == :expected
        assert Calculator.mult(1, 1) == :stubbed
        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "allowances are transitive" do
      parent_pid = self()

      child_pid =
        spawn_link(fn ->
          receive do
            :call_mock ->
              add_result = Calculator.add(1, 1)
              mult_result = Calculator.mult(1, 1)
              send(parent_pid, {:verify, add_result, mult_result})
          end
        end)

      transitive_pid =
        spawn_link(fn ->
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

      spawn_link(fn ->
        Calculator
        |> expect(:add, fn _, _ -> :expected end)
        |> stub(:mult, fn _, _ -> :stubbed end)
        |> allow(self(), parent_pid)

        send(parent_pid, :ok)
      end)

      assert_receive :ok

      assert Calculator.add(1, 3) == 4

      Calculator
      |> expect(:add, fn x, y -> x + y + 7 end)

      assert Calculator.add(1, 1) == 9
    end

    test "raises if you try to allow process while in global mode" do
      set_mimic_global()
      parent_pid = self()
      child_pid = spawn_link(fn -> Process.sleep(:infinity) end)

      spawn_link(fn ->
        assert_raise ArgumentError, "Allow must not be called when mode is global.", fn ->
          Calculator
          |> allow(self(), child_pid)
        end

        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end
  end

  describe "mode/0 global mode" do
    setup :set_mimic_global

    test "returns :global" do
      assert Mimic.mode() == :global
    end
  end

  describe "mode/0 private mode" do
    setup :set_mimic_private

    test "returns :private" do
      assert Mimic.mode() == :private
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

  describe "copy/1 with duplicates" do
    setup :set_mimic_private

    test "stubs still stub" do
      parent_pid = self()

      Mimic.copy(Calculator)
      Mimic.copy(Calculator)

      Calculator
      |> stub(:add, fn x, y ->
        send(parent_pid, {:add, x, y})
        :stubbed
      end)

      Mimic.copy(Calculator)

      assert Calculator.add(1, 2) == :stubbed
      assert_receive {:add, 1, 2}
    end
  end

  describe "call_original/3" do
    setup :set_mimic_private

    test "calls original function even if it has been is stubbed" do
      stub_with(Calculator, InverseCalculator)

      assert call_original(Calculator, :add, [1, 2]) == 3
    end

    test "calls original function even if it has been rejected as a module function" do
      Mimic.reject(Calculator, :add, 2)

      assert call_original(Calculator, :add, [1, 2]) == 3
    end

    test "calls original function even if it has been rejected as a capture" do
      Mimic.reject(&Calculator.add/2)

      assert call_original(Calculator, :add, [1, 2]) == 3
    end

    test "when called on a function that has not been stubbed" do
      assert call_original(Calculator, :add, [1, 2]) == 3
    end

    test "when called on a module that does not exist" do
      assert_raise ArgumentError, "Function add/2 not defined for NonExistentModule", fn ->
        call_original(NonExistentModule, :add, [1, 2])
      end
    end

    test "when called on a function that does not exist" do
      assert_raise ArgumentError, "Function non_existent_call/2 not defined for Calculator", fn ->
        call_original(Calculator, :non_existent_call, [1, 2])
      end
    end
  end

  describe "structs" do
    setup :set_mimic_private

    test "copies struct fields with required fields" do
      Structs
      |> stub(:foo, fn -> :stubbed end)

      assert Structs.__info__(:struct) == [
               %{field: :foo, required: true},
               %{field: :bar, required: true},
               %{field: :default, required: false},
               %{field: :map_default, required: false}
             ]
    end

    test "copies struct fields with default values" do
      Structs
      |> stub(:foo, fn -> :stubbed end)

      assert Structs.__struct__() == %Structs{
               foo: nil,
               bar: nil,
               default: "123",
               map_default: %{}
             }
    end

    test "copies struct fields" do
      StructNoEnforceKeys
      |> stub(:bar, fn -> :stubbed end)

      assert StructNoEnforceKeys.__info__(:struct) == [
               %{field: :foo, required: false},
               %{field: :bar, required: false}
             ]
    end

    test "protocol still works" do
      Structs
      |> stub(:foo, fn -> :stubbed end)

      s = %Structs{foo: "abc", bar: "def"}

      assert to_string(s) == "{abc} - {def}"
    end
  end
end
