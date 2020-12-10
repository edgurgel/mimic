defmodule Mimic.DSL do
  @doc false
  defmacro __using__(_opts) do
    quote do
      import Mimic, except: [allow: 3, expect: 3, except: 4]
      import Mimic.DSL
      setup :verify_on_exit!
    end
  end

  defmacro allow({{:., _, [module, f]}, _, args}, opts) do
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

  defmacro allow({:when, _, [{{:., _, [module, f]}, _, args}, guard_args]}, opts) do
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
