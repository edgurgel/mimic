defmodule Mimic.TestCover do
  @moduledoc false

  @doc false
  def start(compile_path, _opts) do
    :cover.stop()
    :cover.start()
    :cover.compile_beam_directory(compile_path |> String.to_charlist())

    fn ->
      execute()
    end
  end

  defp execute do
    {:result, results, _fail} = :cover.analyse(:calls, :function)

    mimic_module_cover =
      Enum.any?(results, fn
        {{Calculator.Mimic.Original.Module, _, _}, _} -> true
        _ -> false
      end)

    expected =
      {{Calculator, :add, 2}, 5} in results &&
        {{Calculator, :mult, 2}, 5} in results &&
        {{NoStubs, :add, 2}, 2} in results && !mimic_module_cover

    unless expected do
      IO.puts("Cover results are incorrect!")
      throw(:test_cover_failed)
    end
  end
end
