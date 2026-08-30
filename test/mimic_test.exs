defmodule Mimic.Test do
  use ExUnit.Case, async: false
  import Mimic

  @expected 100
  @expected_1 200
  @expected_2 300

  @stubbed 400
  @private_stub 500
  @elixir_version System.version() |> Float.parse() |> elem(0)

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
      pid =
        spawn_link(fn ->
          Mimic.set_mimic_global()
          stub(Calculator, :add, fn _, _ -> @stubbed end)

          pid =
            spawn_link(fn ->
              assert Calculator.add(3, 7) == @stubbed
            end)

          Process.monitor(pid)
          assert_receive {:DOWN, _, _, ^pid, _}
          refute Process.alive?(pid)
        end)

      Process.monitor(pid)
      assert_receive {:DOWN, _, _, ^pid, _}
      refute Process.alive?(pid)

      :timer.sleep(1)

      stub(Calculator, :add, fn _, _ -> @private_stub end)
      assert Calculator.add(3, 7) == @private_stub
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

    test "prefers the current process stub over caller stubs" do
      stub(Calculator, :add, fn _, _ -> @stubbed end)

      results =
        for _ <- 1..100 do
          Task.async(fn ->
            stub(Calculator, :add, fn _, _ -> @expected end)
            Calculator.add(1, 2)
          end)
          |> Task.await()
        end

      assert Enum.uniq(results) == [@expected]
      assert Calculator.add(1, 2) == @stubbed
    end

    test "does not fail verification if not called" do
      stub(Calculator, :add, fn x, y -> x + y end)
      verify!()
    end

    test "respects calls precedence" do
      Calculator
      |> stub(:add, fn x, y -> x + y end)
      |> expect(:add, fn _, _ -> @expected end)

      assert Calculator.add(1, 1) == @expected
      verify!()
    end

    test "allows multiple invocations" do
      stub(Calculator, :add, fn x, y -> x + y end)
      assert Calculator.add(1, 2) == 3
      assert Calculator.add(3, 4) == 7
    end

    test "return stub when all expectations are fulfilled and another call is made" do
      Calculator
      |> stub(:add, fn _x, _y -> @stubbed end)
      |> expect(:add, fn _, _ -> @expected_1 end)
      |> expect(:add, fn _, _ -> @expected_2 end)

      assert Calculator.add(1, 1) == @expected_1
      assert Calculator.add(1, 1) == @expected_2
      assert Calculator.add(1, 1) == @stubbed

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
      |> expect(:add, fn _, _ -> @expected end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(1, 1) == @expected

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

    test "raise when all expectations are fulfilled and another call is made" do
      Calculator
      |> stub(:add, fn _x, _y -> @stubbed end)
      |> expect(:add, fn _, _ -> @expected end)
      |> expect(:add, fn _, _ -> @expected end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(1, 1) == @expected
        assert Calculator.add(1, 1) == @expected
        assert Calculator.add(1, 1) == @stubbed

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
      |> expect(:add, fn _x, _y -> @expected_1 end)
      |> expect(:add, fn _x, _y -> @expected_2 end)

      assert Calculator.add(4, 0) == @expected_1
      assert Calculator.add(5, 0) == @expected_2
    end

    test "expect multiple calls" do
      Calculator
      |> expect(:add, 2, fn x, y -> x + y + 1 end)

      assert Calculator.add(4, 3) == 4 + 3 + 1
      assert Calculator.add(5, 2) == 5 + 2 + 1
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

    test "raise when all expectations are fulfilled and another call is made" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      assert Calculator.add(4, 0) == 4 + 2
      assert Calculator.mult(5, 0) == 5 * 2

      message =
        ~r"Calculator.mult/2 called in process #PID<.*> but expectations are already fulfilled"

      assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.mult(5, 3) end
    end

    test "expectation can be added after being fulfilled" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      assert Calculator.add(4, 0) == 4 + 2
      assert Calculator.mult(5, 0) == 5 * 2

      message =
        ~r"Calculator.mult/2 called in process #PID<.*> but expectations are already fulfilled"

      assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.mult(5, 3) end

      Calculator
      |> expect(:mult, fn x, _y -> x * 2 end)

      assert Calculator.mult(4, 0) == 4 * 2

      message =
        ~r"Calculator.mult/2 called in process #PID<.*> but expectations are already fulfilled"

      assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.mult(5, 3) end
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

    test "macros" do
      expect(Calculator, :add, fn x, _y -> x + 2 end)

      quote do
        require Calculator

        assert Calculator.add(4, 2) == Calculator.add_macro(4, 2)
      end
      |> Code.eval_quoted()
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

    test "expectation on a function and call others" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)

      assert Calculator.add(4, :_) == 6
      assert Calculator.mult(5, 2) == 10
    end

    test "stacking expectations" do
      Calculator
      |> expect(:add, fn _x, _y -> @expected_1 end)
      |> expect(:add, fn _x, _y -> @expected_2 end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(4, 0) == @expected_1
        assert Calculator.add(5, 0) == @expected_2

        send(parent_pid, :ok)
      end)

      assert_receive :ok
    end

    test "expect multiple calls" do
      Calculator
      |> expect(:add, 2, fn x, y -> x + y + 1 end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(4, 3) == 4 + 3 + 1
        assert Calculator.add(5, 2) == 5 + 2 + 1

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

    test "raise when all expectations are fulfilled and another call is made" do
      Calculator
      |> expect(:add, fn x, _y -> x + 2 end)
      |> expect(:mult, fn x, _y -> x * 2 end)

      parent_pid = self()

      spawn_link(fn ->
        assert Calculator.add(4, :_) == 6
        assert Calculator.mult(5, :_) == 10

        message =
          ~r"Calculator.mult/2 called in process #PID<.*> but expectations are already fulfilled"

        assert_raise Mimic.UnexpectedCallError, message, fn -> Calculator.mult(5, 3) end

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
      |> expect(:add, fn _, _ -> @expected end)
      |> stub(:mult, fn _, _ -> @stubbed end)
      |> allow(self(), child_pid)

      send(child_pid, :call_mock)

      assert_receive {:verify, add_result, mult_result}
      assert add_result == @expected
      assert mult_result == @stubbed
    end

    test "allows different processes to share mocks from parent process when allow is defined first" do
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
      |> allow(self(), child_pid)
      |> expect(:add, fn _, _ -> @expected end)
      |> stub(:mult, fn _, _ -> @stubbed end)

      send(child_pid, :call_mock)

      assert_receive {:verify, add_result, mult_result}
      assert add_result == @expected
      assert mult_result == @stubbed
    end

    test "doesn't raise if no expectation defined" do
      child_pid = spawn_link(fn -> :ok end)

      Calculator
      |> allow(self(), child_pid)
    end

    test "allows different processes to share mocks from child process" do
      parent_pid = self()

      Calculator
      |> expect(:add, fn _, _ -> @expected end)
      |> stub(:mult, fn _, _ -> @stubbed end)

      spawn_link(fn ->
        Calculator
        |> allow(parent_pid, self())

        assert Calculator.add(1, 1) == @expected
        assert Calculator.mult(1, 1) == @stubbed
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
      |> expect(:add, fn _, _ -> @expected end)
      |> stub(:mult, fn _, _ -> @stubbed end)
      |> allow(self(), transitive_pid)

      send(transitive_pid, :allow_mock)

      receive do
        {:verify, add_result, mult_result} ->
          assert add_result == @expected
          assert mult_result == @stubbed
          verify!()
      after
        1000 -> verify!()
      end
    end

    test "allowances are reclaimed if the owner process dies" do
      parent_pid = self()

      pid =
        spawn_link(fn ->
          Calculator
          |> expect(:add, fn _, _ -> @expected end)
          |> stub(:mult, fn _, _ -> @stubbed end)
          |> allow(self(), parent_pid)
        end)

      Process.monitor(pid)
      assert_receive {:DOWN, _, _, ^pid, _}
      refute Process.alive?(pid)

      :timer.sleep(1)

      assert Calculator.add(1, 3) == 4

      Calculator
      |> expect(:add, fn x, y -> x + y + 7 end)

      assert Calculator.add(1, 1) == 9
    end

    test "removes the allowed pid's own ownership row when the allowed pid dies" do
      parent_pid = self()

      allowed_pid =
        spawn(fn ->
          # Registers this process as an owner (of an unrelated stub) so that
          # Mimic.Server monitors it directly, independent of the allow row
          # asserted on below.
          Calculator |> stub(:mult, fn _, _ -> :unused end)
          Calculator |> allow(parent_pid, self())

          send(parent_pid, :ready)

          receive do
            :done -> :ok
          end
        end)

      assert_receive :ready
      assert :ets.lookup(Mimic.Coordinator, {allowed_pid, Calculator}) != []

      ref = Process.monitor(allowed_pid)
      send(allowed_pid, :done)
      assert_receive {:DOWN, ^ref, :process, ^allowed_pid, :normal}

      :timer.sleep(1)

      assert :ets.lookup(Mimic.Coordinator, {allowed_pid, Calculator}) == []
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

  describe "allow/3 with function allowances" do
    setup :set_mimic_private
    setup :verify_on_exit!

    test "allows a process to share mocks once its pid is discovered lazily" do
      parent_pid = self()
      name = :"lazy_calc_#{System.unique_integer([:positive])}"

      Calculator
      |> expect(:add, fn x, y -> x + y + 100 end)
      |> allow(self(), fn -> Process.whereis(name) end)

      spawn_link(fn ->
        Process.register(self(), name)
        result = Calculator.add(1, 2)
        send(parent_pid, {:result, result})
      end)

      assert_receive {:result, 103}
    end

    test "uses $callers property from Task to allow lazily" do
      parent_pid = self()
      name = :"lazy_ancestor_#{System.unique_integer([:positive])}"

      Calculator
      |> expect(:add, fn x, y -> x + y + 100 end)
      |> allow(self(), fn -> Process.whereis(name) end)

      spawn_link(fn ->
        Process.register(self(), name)

        result =
          Task.async(fn -> Calculator.add(1, 2) end)
          |> Task.await()

        send(parent_pid, {:result, result})
      end)

      assert_receive {:result, 103}
    end

    test "lazy function is called on each mock invocation" do
      parent_pid = self()
      name = :"lazy_cache_#{System.unique_integer([:positive])}"
      counter = :counters.new(1, [:atomics])

      Calculator
      |> expect(:add, 2, fn x, y -> x + y + 100 end)
      |> allow(self(), fn ->
        :counters.add(counter, 1, 1)
        Process.whereis(name)
      end)

      spawn_link(fn ->
        Process.register(self(), name)
        Calculator.add(1, 2)
        Calculator.add(3, 4)
        send(parent_pid, :done)
      end)

      assert_receive :done
      assert :counters.get(counter, 1) == 2
    end

    test "does not create a duplicate monitor when the same owner allows with a function more than once" do
      parent_pid = self()
      coordinator_pid = Process.whereis(Mimic.Coordinator)

      owner_pid =
        spawn(fn ->
          Calculator |> stub(:add, fn _, _ -> 1 end) |> allow(self(), fn -> nil end)
          Counter |> stub(:inc, fn x -> x end) |> allow(self(), fn -> nil end)
          send(parent_pid, :ready)

          receive do
            :done -> :ok
          end
        end)

      assert_receive :ready

      {:monitors, monitors} = Process.info(coordinator_pid, :monitors)
      owner_monitor_count = Enum.count(monitors, fn {:process, pid} -> pid == owner_pid end)

      send(owner_pid, :done)

      assert owner_monitor_count == 1
    end

    test "supports lazy allowances that return a list of pids" do
      parent_pid = self()
      name_a = :"lazy_list_a_#{System.unique_integer([:positive])}"
      name_b = :"lazy_list_b_#{System.unique_integer([:positive])}"

      Calculator
      |> stub(:add, fn x, y -> x + y + 200 end)
      |> allow(self(), fn -> [Process.whereis(name_a), Process.whereis(name_b)] end)

      spawn_link(fn ->
        Process.register(self(), name_a)
        send(parent_pid, {:a, Calculator.add(5, 6)})
      end)

      spawn_link(fn ->
        Process.register(self(), name_b)
        send(parent_pid, {:b, Calculator.add(7, 8)})
      end)

      assert_receive {:a, 211}
      assert_receive {:b, 215}
    end

    test "falls through to original when lazy function returns nil" do
      allow(Calculator, self(), fn -> nil end)
      assert Calculator.add(2, 3) == 5
    end

    test "falls through to original when the lazy function returns something other than a pid, list of pids, or nil" do
      parent_pid = self()

      Calculator
      |> stub(:add, fn _, _ -> :should_not_be_reached end)
      |> allow(self(), fn -> :not_a_pid end)

      spawn_link(fn -> send(parent_pid, {:result, Calculator.add(2, 3)}) end)

      assert_receive {:result, 5}
    end

    test "falls through to original when the lazy function returns a list containing only non-pids" do
      parent_pid = self()

      Calculator
      |> stub(:add, fn _, _ -> :should_not_be_reached end)
      |> allow(self(), fn -> [:not_a_pid, :also_not_a_pid] end)

      spawn_link(fn -> send(parent_pid, {:result, Calculator.add(2, 3)}) end)

      assert_receive {:result, 5}
    end

    test "falls through to original when the lazy function raises" do
      parent_pid = self()

      Calculator
      |> stub(:add, fn _, _ -> :should_not_be_reached end)
      |> allow(self(), fn -> raise "boom" end)

      spawn_link(fn -> send(parent_pid, {:result, Calculator.add(2, 3)}) end)

      assert_receive {:result, 5}
    end

    test "matches a pid returned alongside an invalid entry in the same list" do
      parent_pid = self()
      name = :"lazy_#{System.unique_integer([:positive])}"

      Calculator
      |> expect(:add, fn _, _ -> :matched end)
      |> allow(self(), fn -> [:not_a_pid, Process.whereis(name)] end)

      spawn_link(fn ->
        Process.register(self(), name)
        send(parent_pid, {:result, Calculator.add(2, 3)})
      end)

      assert_receive {:result, :matched}
    end

    test "a raising lazy allowance from one owner does not block a different owner's matching lazy allowance" do
      parent_pid = self()
      name = :"lazy_#{System.unique_integer([:positive])}"

      _other_owner =
        spawn(fn ->
          Calculator
          |> stub(:add, fn _, _ -> :should_not_be_reached end)
          |> allow(self(), fn -> raise "BOOM! Unrelated owner's bad callback." end)

          send(parent_pid, :other_owner_ready)

          # Keep this procees alive so its lazy allowance stays in effect
          receive do
            :done -> :ok
          end
        end)

      assert_receive :other_owner_ready

      Calculator
      |> expect(:add, fn _, _ -> :matched end)
      |> allow(self(), fn -> Process.whereis(name) end)

      spawn_link(fn ->
        Process.register(self(), name)
        send(parent_pid, {:result, Calculator.add(2, 3)})
      end)

      assert_receive {:result, :matched}
    end

    test "supports stubs" do
      parent_pid = self()
      name = :"lazy_stub_#{System.unique_integer([:positive])}"

      Calculator
      |> stub(:add, fn x, y -> x * y end)
      |> allow(self(), fn -> Process.whereis(name) end)

      spawn_link(fn ->
        Process.register(self(), name)
        result = Calculator.add(3, 4)
        send(parent_pid, {:result, result})
      end)

      assert_receive {:result, 12}
    end

    test "lazy allowances are reclaimed if the owner process dies" do
      parent_pid = self()
      name = :"lazy_cleanup_#{System.unique_integer([:positive])}"

      # This would usually be the test pid, but we need it to die independently
      # of our test process here so we can verify that the lazy allowance is
      # cleaned up as expected.
      owner_pid =
        spawn(fn ->
          Calculator
          |> stub(:add, fn _, _ -> 999 end)
          |> allow(self(), fn -> Process.whereis(name) end)
        end)

      # Stays alive and registered beyond the owner's death so the lazy function
      # keeps resolving successfully.
      allowed_pid =
        spawn_link(fn ->
          Process.register(self(), name)

          receive do
            :call_add -> send(parent_pid, {:result, Calculator.add(1, 3)})
          end
        end)

      Process.monitor(owner_pid)
      assert_receive {:DOWN, _, _, ^owner_pid, _}

      :timer.sleep(1)

      assert :ets.match_object(:lazy_modules, {Calculator, owner_pid, :_}) == []

      # After owner dies, lazy allowance should be gone — calls fall through to original
      send(allowed_pid, :call_add)

      assert_receive {:result, 4}
    end

    test "lazy allowances are transitive" do
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
            :allow_lazy ->
              Calculator
              |> allow(self(), fn -> child_pid end)

              send(child_pid, :call_mock)
          end
        end)

      Calculator
      |> expect(:add, fn _, _ -> @expected end)
      |> stub(:mult, fn _, _ -> @stubbed end)
      |> allow(self(), transitive_pid)

      send(transitive_pid, :allow_lazy)

      assert_receive {:verify, add_result, mult_result}
      assert add_result == @expected
      assert mult_result == @stubbed
    end

    test "lazy allowances are reclaimed if the transitively resolved owner dies" do
      parent_pid = self()
      name = :"lazy_transitive_cleanup_#{System.unique_integer([:positive])}"

      transitive_pid =
        spawn_link(fn ->
          receive do
            :allow_lazy ->
              Calculator
              |> allow(self(), fn -> Process.whereis(name) end)

              send(parent_pid, :lazy_allow_done)
          end
        end)

      owner_pid =
        spawn(fn ->
          Calculator
          |> stub(:add, fn _, _ -> 999 end)
          |> allow(self(), transitive_pid)

          send(parent_pid, :owner_ready)

          receive do
            :die -> :ok
          end
        end)

      assert_receive :owner_ready

      send(transitive_pid, :allow_lazy)
      assert_receive :lazy_allow_done

      allowed_pid =
        spawn_link(fn ->
          Process.register(self(), name)

          receive do
            :call_add -> send(parent_pid, {:result, Calculator.add(1, 3)})
          end
        end)

      refute :ets.match_object(:lazy_modules, {Calculator, owner_pid, :_}) == []

      Process.monitor(owner_pid)
      send(owner_pid, :die)
      assert_receive {:DOWN, _, _, ^owner_pid, _}
      :timer.sleep(1)

      assert :ets.match_object(:lazy_modules, {Calculator, owner_pid, :_}) == []

      # After owner dies, lazy allowance should be gone — calls fall through to original
      send(allowed_pid, :call_add)
      assert_receive {:result, 4}
    end

    test "raises if you try to allow with function while in global mode" do
      set_mimic_global()

      assert_raise ArgumentError, "Allow must not be called when mode is global.", fn ->
        allow(Calculator, self(), fn -> self() end)
      end
    end

    test "lazy allowances registered under private mode do not apply after switching to global mode" do
      parent_pid = self()
      name = :"lazy_mode_switch_#{System.unique_integer([:positive])}"

      Calculator
      |> stub(:add, fn _, _ -> 999 end)
      |> allow(self(), fn -> Process.whereis(name) end)

      allowed_pid =
        spawn_link(fn ->
          Process.register(self(), name)

          receive do
            :call_add -> send(parent_pid, {:result, Calculator.add(1, 3)})
          end
        end)

      spawn_link(fn ->
        Mimic.set_mimic_global()
        send(parent_pid, :global_set)
      end)

      assert_receive :global_set

      # allowed_pid's lazy allowance was registered while mode was private, and
      # the global owner never stubbed Calculator. The call should fall through
      # to the original implementation rather than resolving through the
      # now-stale private-mode allowance.
      send(allowed_pid, :call_add)
      assert_receive {:result, 4}
    end
  end

  describe "mode/0 global mode" do
    setup :set_mimic_global

    test "returns :global" do
      assert Mimic.mode() == :global
    end
  end

  describe "global mode dispatch with a stale allowance row" do
    test "routes to the mode-row owner, not a stale allowance row's value" do
      # A prior private-mode test can leave behind an allowance row keyed at
      # what later becomes the global owner but whose *stored value* is a
      # different owner.
      set_mimic_private()
      stale_owner = spawn_link(fn -> Process.sleep(:infinity) end)

      assert Calculator == allow(Calculator, stale_owner, self())

      # Go global with self() as the owner and set an expectation. The ownership
      # row is written with insert_new, so the stale allowance row survives.
      set_mimic_global()
      Calculator |> expect(:add, fn _, _ -> 999_999 end)

      # Dispatch must use self() (the pid in the :mode row), not stale_owner.
      # Under the old code find_owner returned stale_owner's value and misrouted
      # to a shard with no expectation, falling through to the original (3).
      assert Calculator.add(1, 2) == 999_999
    end
  end

  describe "mode/0 private mode" do
    setup :set_mimic_private

    test "returns :private" do
      assert Mimic.mode() == :private
    end
  end

  describe "behaviours" do
    setup :set_mimic_private

    test "copies behaviour attributes" do
      behaviours =
        Calculator.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert AddAdapter in behaviours
      assert MultAdapter in behaviours
    end

    test "Regression test for PR #105: doesn't remove behaviour_info/1" do
      Mimic.copy(MultAdapter)

      stub(MultAdapter)
      expect(MultAdapter, :behaviour_info, fn :callbacks -> [mult: 2] end)

      assert MultAdapter.behaviour_info(:callbacks) == [mult: 2]
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
        @stubbed
      end)

      Mimic.copy(Calculator)

      assert Calculator.add(1, 2) == @stubbed
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

    test "copies struct fields with default values" do
      Structs
      |> stub(:foo, fn -> @stubbed end)

      assert Structs.__struct__() == %Structs{
               foo: nil,
               bar: nil,
               default: "123",
               map_default: %{}
             }
    end

    cond do
      @elixir_version >= 1.19 ->
        test "copies struct fields" do
          StructNoEnforceKeys
          |> stub(:bar, fn -> @stubbed end)

          # Why pattern matching:
          # Direct comparison causes the compiler to emit a warning.
          # The `default` key may or may not exist in the struct info.
          assert [
                   %{field: :foo, default: nil, required: false},
                   %{field: :bar, default: nil, required: false}
                 ] = StructNoEnforceKeys.__info__(:struct)
        end

      @elixir_version >= 1.18 ->
        test "copies struct fields" do
          StructNoEnforceKeys
          |> stub(:bar, fn -> @stubbed end)

          assert StructNoEnforceKeys.__info__(:struct) == [
                   %{field: :foo, default: nil},
                   %{field: :bar, default: nil}
                 ]
        end

      true ->
        test "copies struct fields" do
          StructNoEnforceKeys
          |> stub(:bar, fn -> @stubbed end)

          assert StructNoEnforceKeys.__info__(:struct) == [
                   %{field: :foo, required: false},
                   %{field: :bar, required: false}
                 ]
        end
    end

    test "protocol still works" do
      Structs
      |> stub(:foo, fn -> @stubbed end)

      s = %Structs{foo: "abc", bar: "def"}

      assert to_string(s) == "{abc} - {def}"
    end
  end

  describe "calls/1" do
    setup :set_mimic_private

    test "returns calls for stubbed functions" do
      stub(Calculator, :add, fn x, y -> x + y end)

      Calculator.add(1, 2)
      Calculator.add(3, 4)

      assert Mimic.calls(&Calculator.add/2) == [[1, 2], [3, 4]]
      assert Mimic.calls(&Calculator.add/2) == []
    end
  end

  describe "calls/3 private mode" do
    setup :set_mimic_private

    test "returns calls for stubbed functions" do
      stub(Calculator, :add, fn x, y -> x + y end)

      Calculator.add(1, 2)
      Calculator.add(3, 4)

      assert Mimic.calls(Calculator, :add, 2) == [[1, 2], [3, 4]]
      assert Mimic.calls(Calculator, :add, 2) == []
    end

    test "returns calls for expected functions" do
      expect(Calculator, :add, 2, fn x, y -> x + y end)

      Calculator.add(1, 2)
      Calculator.add(3, 4)

      assert Mimic.calls(Calculator, :add, 2) == [[1, 2], [3, 4]]
      assert Mimic.calls(Calculator, :add, 2) == []
    end

    test "return calls from child pid as well" do
      parent_pid = self()

      Calculator
      |> expect(:add, fn _, _ -> @expected end)
      |> stub(:mult, fn _, _ -> @stubbed end)

      spawn_link(fn ->
        Calculator
        |> allow(parent_pid, self())

        assert Calculator.add(1, 2) == @expected
        assert Calculator.mult(3, 4) == @stubbed
        send(parent_pid, :ok)
      end)

      assert_receive :ok
      assert Mimic.calls(&Calculator.add/2) == [[1, 2]]
      assert Mimic.calls(&Calculator.add/2) == []

      assert Mimic.calls(&Calculator.mult/2) == [[3, 4]]
      assert Mimic.calls(&Calculator.mult/2) == []
    end

    test "raises when mock is not defined" do
      assert_raise ArgumentError, fn -> Mimic.calls(Date, :add, 2) end
    end

    test "raises for non-existent functions" do
      assert_raise ArgumentError,
                   "Function invalid/2 not defined for Calculator",
                   fn -> Mimic.calls(Calculator, :invalid, 2) end
    end

    test "raises for non-existent modules" do
      assert_raise ArgumentError, "Function add/2 not defined for NonExistentModule", fn ->
        Mimic.calls(NonExistentModule, :add, 2)
      end
    end
  end

  describe "calls/3 global mode" do
    setup :set_mimic_global

    test "returns calls for stubbed functions" do
      stub(Calculator, :add, fn x, y -> x + y end)

      parent_pid = self()

      spawn_link(fn ->
        Calculator.add(1, 2)
        Calculator.add(3, 4)
        send(parent_pid, :ok)
      end)

      assert_receive :ok
      assert Mimic.calls(Calculator, :add, 2) == [[1, 2], [3, 4]]
      assert Mimic.calls(Calculator, :add, 2) == []
    end

    test "returns calls for expected functions" do
      expect(Calculator, :add, 2, fn x, y -> x + y end)

      parent_pid = self()

      spawn_link(fn ->
        Calculator.add(1, 2)
        Calculator.add(3, 4)
        send(parent_pid, :ok)
      end)

      assert_receive :ok
      assert Mimic.calls(Calculator, :add, 2) == [[1, 2], [3, 4]]
      assert Mimic.calls(Calculator, :add, 2) == []
    end

    test "raises when mock is not defined" do
      assert_raise ArgumentError, fn -> Mimic.calls(Date, :add, 2) end
    end

    test "raises for non-existent functions" do
      assert_raise ArgumentError,
                   "Function invalid/2 not defined for Calculator",
                   fn -> Mimic.calls(Calculator, :invalid, 2) end
    end

    test "raises for non-existent modules" do
      assert_raise ArgumentError, "Function add/2 not defined for NonExistentModule", fn ->
        Mimic.calls(NonExistentModule, :add, 2)
      end
    end
  end

  describe "verify_on_exit!/1" do
    setup :set_mimic_private

    test "cleans up when exit verification raises" do
      # This process stands in for an ExUnit test process. Registering it with
      # ExUnit allows verify_on_exit!/0 to install its real on-exit callback.
      {test_pid, monitor_ref} =
        spawn_monitor(fn ->
          ExUnit.OnExitHandler.register(self())
          verify_on_exit!()

          # Leave an expectation pending so verification raises on exit.
          expect(Calculator, :add, fn x, y -> x + y end)
        end)

      assert_receive {:DOWN, ^monitor_ref, :process, ^test_pid, :normal}

      # Run the registered callback manually so its expected verification error
      # can be asserted without failing this test.
      assert {:error, %Mimic.VerificationError{}, _stacktrace} =
               ExUnit.OnExitHandler.run(test_pid, 1_000)

      # The callback cleaned up the pending expectation even though verification raised.
      assert Mimic.Server.verify(test_pid) == []
    end
  end

  describe "set_mimic_global/1" do
    test "raises if the test case is async" do
      message = ~r/Mimic cannot be set to global mode when the ExUnit case is async/
      assert_raise RuntimeError, message, fn -> set_mimic_global(%{async: true}) end
    end
  end
end
