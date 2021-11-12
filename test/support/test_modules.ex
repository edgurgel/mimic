defmodule AddAdapter do
  @moduledoc false
  @callback add(number(), number()) :: number()
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
