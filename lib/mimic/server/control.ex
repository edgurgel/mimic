defmodule Mimic.Server.Control do
  use GenServer
  @moduledoc false

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    table = Keyword.fetch!(opts, :ownership_table)

    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    :ets.new(table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.insert(table, {:mode, :private})

    {:ok, %{ownership_table: table}}
  end
end
