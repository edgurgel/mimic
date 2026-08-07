defmodule Mimic.Application do
  use Application
  @moduledoc false

  def start(_, _) do
    children = [
      Mimic.Coordinator,
      {PartitionSupervisor, child_spec: Mimic.Server, name: Mimic.Server.Partitions}
    ]

    # rest_for_one: the Coordinator owns the shared ETS table so let's restart the Servers
    # if something goes wrong with it
    Supervisor.start_link(children, name: Mimic.Supervisor, strategy: :rest_for_one)
  end
end
