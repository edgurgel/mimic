defmodule Mimic.TestCaseWithSomeDefaultStub do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Mimic.TestCaseWithSomeDefaultStub
    end
  end

  setup do
    Mimic.stub(Calculator, :add, fn _, _ -> 1 end)
    :ok
  end
end
