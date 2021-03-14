defmodule EstoqueDeCasaBot.Pessoa do
  use GenServer

  defstruct id: 0,
            nome: "",
            chat_id: "",
            novo_produto: nil,
            produtos: [],
            estado_atual: :esperando

  alias __MODULE__
  alias EstoqueDeCasaBot.TelegramClient
  alias EstoqueDeCasaBot.Produto

  def start_link(%Pessoa{id: id} = pessoa) do
    GenServer.start_link(__MODULE__, pessoa, name: process_name(id))
  end

  defp process_name(id) do
    {:via, Registry, {EstoqueDeCasaBot.PessoaRegistry, "pessoa_#{id}"}}
  end

  @impl true
  def init(pessoa) do
    {:ok, pessoa}
  end

  def get_by(%{id: id}) do
    Registry.lookup(EstoqueDeCasaBot.PessoaRegistry, "pessoa_#{id}")
    |> case do
      [] -> nil
      [{pessoa_pid, _}] -> pessoa_pid
    end
  end

  def get_estado_atual(pessoa_pid) do
    GenServer.call(pessoa_pid, :get_estado_atual)
  end

  def new(%{id: _id, nome: _nome, chat_id: _chat_id} = nova_pessoa) do
    pessoa = struct(Pessoa, nova_pessoa)

    {:ok, pessoa_pid} =
      DynamicSupervisor.start_child(EstoqueDeCasaBot.PessoaSupervisor, {Pessoa, pessoa})

    pessoa_pid
  end

  def listar_produtos(pessoa_pid) do
    GenServer.call(pessoa_pid, :listar_produtos)
    |> case do
      [] ->
        enviar_mensagem(pessoa_pid, "Você não tem nenhum produto ainda.")

      produtos ->
        mensagem =
          produtos
          |> Enum.reduce("Seus produtos!\n\n", fn produto, mensagem ->
            mensagem <>
              "Produto: #{produto.nome}, com #{produto.quantidade_atual}, mímino de #{
                produto.quantidade_minima
              }\n"
          end)

        enviar_mensagem(pessoa_pid, mensagem)
    end
  end

  def enviar_mensagem(pessoa_pid, message) do
    GenServer.cast(pessoa_pid, {:enviar_mensagem, message})
  end

  def cadastrar_produto(pessoa_pid) do
    %Produto{
      nome: nome,
      quantidade_atual: quantidade_atual,
      quantidade_minima: quantidade_minima
    } = GenServer.call(pessoa_pid, :cadastrar_produto)

    enviar_mensagem(
      pessoa_pid,
      "Produto cadastrado!\n\n#{nome}, com #{quantidade_atual} atualmente, tendo no mínimo #{
        quantidade_minima
      }"
    )
  end

  def iniciar_cadastro_de_produto(pessoa_pid) do
    GenServer.call(pessoa_pid, :iniciar_cadastro_de_produto)

    enviar_mensagem(
      pessoa_pid,
      "OK! Vamos cadastrar um novo produto!\nQual é o nome do novo produto?"
    )
  end

  def salvar_nome_novo_produto(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:salvar_nome_novo_produto, mensagem})

    enviar_mensagem(
      pessoa_pid,
      "Boa! Agora, quantas unidades você tem atualmente desse produto?"
    )
  end

  def salvar_quantidade_atual_novo_produto(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:salvar_quantidade_atual_novo_produto, mensagem})

    enviar_mensagem(
      pessoa_pid,
      "Quase lá! Qual é a quantidade mímina que você precisa ter desse produto?"
    )
  end

  def salvar_quantidade_minima_novo_produto(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:salvar_quantidade_minima_novo_produto, mensagem})
    cadastrar_produto(pessoa_pid)
  end

  @impl true
  def handle_cast({:enviar_mensagem, message}, %Pessoa{chat_id: chat_id} = pessoa) do
    TelegramClient.send_response(chat_id, message)
    {:noreply, pessoa}
  end

  @impl true
  def handle_call(:listar_produtos, _from, %Pessoa{produtos: produtos} = pessoa) do
    {:reply, produtos, pessoa}
  end

  def handle_call(:cadastrar_produto, _from, %Pessoa{novo_produto: novo_produto} = pessoa) do
    {:reply, novo_produto,
     %Pessoa{pessoa | produtos: pessoa.produtos ++ [novo_produto], novo_produto: %Produto{}}}
  end

  def handle_call(:iniciar_cadastro_de_produto, _from, %Pessoa{} = pessoa) do
    {:reply, :ok, %Pessoa{pessoa | estado_atual: :cadastrando_produto, novo_produto: %Produto{}}}
  end

  def handle_call(
        {
          :salvar_nome_novo_produto,
          nome
        },
        _from,
        %Pessoa{
          novo_produto: %Produto{} = produto
        } = pessoa
      ) do
    {:reply, :ok,
     %Pessoa{
       pessoa
       | estado_atual: :cadastrando_quantidade_atual,
         novo_produto: %Produto{produto | nome: nome}
     }}
  end

  def handle_call(
        {
          :salvar_quantidade_atual_novo_produto,
          quantidade_atual
        },
        _from,
        %Pessoa{
          novo_produto: %Produto{} = produto
        } = pessoa
      ) do
    {:reply, :ok,
     %Pessoa{
       pessoa
       | estado_atual: :cadastrando_quantidade_minima,
         novo_produto: %Produto{
           produto
           | quantidade_atual: quantidade_atual |> String.to_integer()
         }
     }}
  end

  def handle_call(
        {
          :salvar_quantidade_minima_novo_produto,
          quantidade_minima
        },
        _from,
        %Pessoa{
          novo_produto: %Produto{} = produto
        } = pessoa
      ) do
    {:reply, :ok,
     %Pessoa{
       pessoa
       | estado_atual: :esperando,
         novo_produto: %Produto{
           produto
           | quantidade_minima: quantidade_minima |> String.to_integer()
         }
     }}
  end

  def handle_call(:get_estado_atual, _from, %Pessoa{estado_atual: estado_atual} = pessoa) do
    {:reply, estado_atual, pessoa}
  end
end