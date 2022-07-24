defmodule Mimic.Application do
  use Application
  alias Mimic.{Cover, Server}
  @moduledoc false

  def start(_, _) do
    Cover.setup_if_enabled()
    children = [Server]
    Supervisor.start_link(children, name: Mimic.Supervisor, strategy: :one_for_one)
  end
end
