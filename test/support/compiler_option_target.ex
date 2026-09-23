defmodule CompilerOptionTarget do
  @moduledoc false

  defstruct value: :original
  defoverridable __struct__: 0

  def __struct__ do
    case Process.get({__MODULE__, :action}) do
      :raise ->
        raise "replacement failed"

      :throw ->
        throw(:replacement_failed)

      :exit ->
        exit(:replacement_failed)

      {:barrier, controller} ->
        send(controller, {:inside_replacement, self()})

        receive do
          :continue -> :ok
        after
          5_000 -> raise "replacement barrier was not released"
        end

      nil ->
        :ok
    end

    super()
  end
end
