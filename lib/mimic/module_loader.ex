defmodule Mimic.ModuleLoader do
  @moduledoc false

  use GenServer

  defp name(module) do
    "#{module}.Loader" |> String.to_atom()
  end

  def rename_module(module) do
    GenServer.call(name(module), {:rename_module, module}, 60_000)
  end

  def start_link(module) do
    GenServer.start_link(__MODULE__, [], name: name(module))
  end

  def init([]) do
    {:ok, nil}
  end

  def handle_call({:rename_module, module}, _from, state) do
    case Mimic.Server.fetch_beam_code(module) do
      [{^module, beam_code, compiler_options}] ->
        Mimic.Module.rename_module(module, beam_code, compiler_options)
        Mimic.Server.delete_beam_code(module)

      _ ->
        :ok
    end

    {:reply, :ok, state}
  end
end
