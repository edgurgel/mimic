defmodule Calculator do
  @moduledoc false
  def add(x, y), do: x + y
  def mult(x, y), do: x * y
end

defmodule Counter do
  @moduledoc false
  def inc(counter), do: counter + 1
  def dec(counter), do: counter - 1
  def add(counter, x), do: counter + x
end
