defmodule AddAdapter do
  @moduledoc false
  @callback add(number(), number()) :: number()
  @macrocallback add_macro(Macro.t(), Macro.t()) :: Macro.t()
  @optional_callbacks add_macro: 2
end

defmodule MultAdapter do
  @moduledoc false
  @callback mult(number(), number()) :: number()
end

defmodule Calculator do
  @moduledoc false
  @behaviour AddAdapter
  @behaviour MultAdapter
  def add(x, y), do: x + y
  defmacro add_macro(x, y), do: {:+, [], [x, y]}
  def mult(x, y), do: x * y
end

defmodule InverseCalculator do
  @moduledoc false
  @behaviour AddAdapter
  def add(x, y), do: x - y
end

defmodule Counter do
  @moduledoc false
  def inc(counter), do: counter + 1
  def dec(counter), do: counter - 1
  def add(counter, x), do: counter + x
end

defmodule Enumerator do
  @moduledoc false
  def to_list(x, y), do: Enum.to_list(x..y)
end

defmodule NoStubs do
  @moduledoc false
  def add(x, y), do: x + y
end

defmodule NotCopiedModule do
  @moduledoc false
  def inc(counter), do: counter - 1
end

defmodule Structs do
  @moduledoc false
  @enforce_keys [:foo, :bar]
  defstruct [:foo, :bar, default: "123", map_default: %{}]
  def foo, do: nil
end

defmodule StructNoEnforceKeys do
  @moduledoc false
  defstruct [:foo, :bar]
  def bar, do: nil
end

defimpl String.Chars, for: Structs do
  def to_string(structs) do
    "{#{structs.foo}} - {#{structs.bar}}"
  end
end

defmodule Typecheck.Counter do
  @moduledoc false

  @spec inc(number) :: number
  def inc(counter), do: counter + 1

  @spec dec(number) :: number
  def dec(counter), do: counter - 1

  @spec add(number, number) :: number
  def add(counter, x), do: counter + x
end

defmodule Typecheck.Calculator do
  @moduledoc false
  @behaviour AddAdapter
  @behaviour MultAdapter

  def add(x, y), do: x + y

  @spec mult(integer, integer) :: integer
  def mult(x, y), do: x * y
end
