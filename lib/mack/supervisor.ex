defmodule Mack.Supervisor do
  use Supervisor

  @name __MODULE__

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_proxy(module, backup_module, opts) do
    Supervisor.start_child(__MODULE__, [module, backup_module, opts])
  end

  def init(:ok) do
    children = [worker(Mack.Proxy, [], restart: :temporary)]

    supervise(children, strategy: :simple_one_for_one)
  end
end
