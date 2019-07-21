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

    results =
      Enum.filter(results, fn
        {{Calculator, _, _}, _} -> true
        _ -> false
      end)

    expected =
      {{Calculator, :add, 2}, 5} in results &&
        {{Calculator, :mult, 2}, 5} in results

    unless expected do
      IO.puts("Cover results are incorrect!")
      throw(:test_cover_failed)
    end
  end
end
