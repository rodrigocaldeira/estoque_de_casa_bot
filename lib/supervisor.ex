defmodule EstoqueDeCasaBot.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    children = [
      EstoqueDeCasaBot.Bot,
      {Registry, keys: :unique, name: EstoqueDeCasaBot.PessoaRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: EstoqueDeCasaBot.PessoaSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
