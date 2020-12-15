defmodule Mimic.DSL do
  @moduledoc """
  stubs and expectations can be expressed in a more natural way

  ```elixir
  use Mimic.DSL
  ```

  ```elixir
  test "basic example" do
    stub Calculator.add(_x, _y), do: :stub
    expect Calculator.add(x, y), do: x + y
    expect Calculator.mult(x, y), do: x * y

    assert Calculator.add(2, 3) == 5
    assert Calculator.mult(2, 3) == 6

    assert Calculator.add(2, 3) == :stub
  end
  ```

  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Mimic, except: [stub: 3, expect: 3, expect: 4]
      import Mimic.DSL
      setup :verify_on_exit!
    end
  end

  defmacro stub({{:., _, [module, f]}, _, args}, opts) do
    body = Keyword.fetch!(opts, :do)

    function =
      quote do
        fn unquote_splicing(args) ->
          unquote(body)
        end
      end

    quote do
      Mimic.stub(unquote(module), unquote(f), unquote(function))
    end
  end

  defmacro stub({:when, _, [{{:., _, [module, f]}, _, args}, guard_args]}, opts) do
    body = Keyword.fetch!(opts, :do)

    function =
      quote do
        fn unquote_splicing(args) when unquote(guard_args) ->
          unquote(body)
        end
      end

    quote do
      Mimic.stub(unquote(module), unquote(f), unquote(function))
    end
  end

  defmacro expect({{:., _, [module, f]}, _, args}, opts) do
    body = Keyword.fetch!(opts, :do)

    function =
      quote do
        fn unquote_splicing(args) ->
          unquote(body)
        end
      end

    quote do
      Mimic.expect(unquote(module), unquote(f), unquote(function))
    end
  end

  defmacro expect({:when, _, [{{:., _, [module, f]}, _, args}, guard_args]}, opts) do
    body = Keyword.fetch!(opts, :do)

    function =
      quote do
        fn unquote_splicing(args) when unquote(guard_args) ->
          unquote(body)
        end
      end

    quote do
      Mimic.expect(unquote(module), unquote(f), unquote(function))
    end
  end
end
