defmodule EstoqueDeCasaBot do
  use Application

  @impl true
  def start(_type, _args) do
    EstoqueDeCasaBot.Supervisor.start_link(name: EstoqueDeCasaBot.Supervisor)
  end
end
