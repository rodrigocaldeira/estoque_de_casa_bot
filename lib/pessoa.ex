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
              "#{produto.nome}, com #{produto.quantidade_atual}, mímino de #{
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
    |> case do
      :ok ->
        enviar_mensagem(
          pessoa_pid,
          "Boa! Agora, quantas unidades você tem atualmente desse produto?"
        )
        
      :produto_ja_cadastrado ->
        enviar_mensagem(
          pessoa_pid,
          "Desculpe, mas você já tem #{mensagem} cadastrado!\nPor favor, informe outro produto (ou digite /cancelar para cancelar o cadastro)"
        )
    end
  end

  def salvar_quantidade_atual_novo_produto(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:salvar_quantidade_atual_novo_produto, mensagem})
    |> case do
      :ok ->

        enviar_mensagem(
          pessoa_pid,
          "Quase lá! Qual é a quantidade mímina que você precisa ter desse produto?"
        )

      :argument_error ->
        enviar_mensagem(
          pessoa_pid,
          "Descupe, mas #{mensagem} é uma quantidade inválida! Vamos tentar novamente?\nQuantas unidades você tem atualmente desse produto?"
        )
    end
  end

  def cancelar_operacao_atual(pessoa_pid) do
    GenServer.call(pessoa_pid, :cancelar_operacao_atual)

    enviar_mensagem(
      pessoa_pid,
      "Cancelado com sucesso! Nenhum produto sendo cadastrado ou atualizado no momento"
    )
  end

  def salvar_quantidade_minima_novo_produto(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:salvar_quantidade_minima_novo_produto, mensagem})
    |> case do
      :ok ->
        cadastrar_produto(pessoa_pid)
      :argument_error ->
        enviar_mensagem(
          pessoa_pid,
          "Descupe, mas #{mensagem} é uma quantidade inválida! Vamos tentar novamente?\nQual é a quantidade mínima que você precisa ter desse produto?"
        )
    end
  end

  def gerar_lista_de_compras(pessoa_pid) do
    lista_de_compras = GenServer.call(pessoa_pid, :gerar_lista_de_compras)

    enviar_mensagem(
      pessoa_pid,
      lista_de_compras
    )
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
          novo_produto: %Produto{} = produto,
          produtos: produtos
        } = pessoa
  ) do
    nome_novo_produto = nome |> String.trim()

    produtos
    |> Enum.find(fn p -> p.nome == nome_novo_produto end)
    |> case do
      nil ->
        {:reply, :ok,
          %Pessoa{
            pessoa
            | estado_atual: :cadastrando_quantidade_atual,
            novo_produto: %Produto{produto | nome: nome_novo_produto}
          }}
      _ ->
        {:reply, :produto_ja_cadastrado, pessoa}
    end
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

    try do
      {:reply, :ok,
        %Pessoa{
          pessoa
          | estado_atual: :cadastrando_quantidade_minima,
          novo_produto: %Produto{
            produto
            | quantidade_atual: quantidade_atual |> String.to_integer()
          }
        }}
    rescue 
      ArgumentError ->
        {:reply, :argument_error, pessoa}
    end
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
    try do

    {:reply, :ok,
     %Pessoa{
       pessoa
       | estado_atual: :esperando,
         novo_produto: %Produto{
           produto
           | quantidade_minima: quantidade_minima |> String.to_integer()
         }
     }}
    rescue
      ArgumentError ->
        {:reply, :argument_error, pessoa}
    end
  end

  def handle_call(:get_estado_atual, _from, %Pessoa{estado_atual: estado_atual} = pessoa) do
    {:reply, estado_atual, pessoa}
  end

  def handle_call(:cancelar_operacao_atual, _from, %Pessoa{} = pessoa) do
    {:reply, :ok, %Pessoa{pessoa | estado_atual: :esperando, novo_produto: %Produto{}}}
  end

  def handle_call(:gerar_lista_de_compras, _from, %Pessoa{produtos: produtos} = pessoa) do
    produtos
    |> listar_produtos_com_estoque_baixo()
    |> case do
      [] ->
        {:reply, "Você não tem nenhum produto cadastrado!", pessoa}

      produtos_com_estoque_baixo ->
        mensagem =
          produtos_com_estoque_baixo
          |> Enum.map(fn %Produto{
                           nome: nome,
                           quantidade_atual: quantidade_atual,
                           quantidade_minima: quantidade_minima
                         } ->
            %{nome: nome, quantidade: quantidade_minima - quantidade_atual}
          end)
          |> Enum.reduce("Segue sua lista de compras!\n\n", fn %{
                                                                 nome: nome,
                                                                 quantidade: quantidade
                                                               },
                                                               mensagem ->
            "#{mensagem}#{nome}, comprar #{quantidade} unidades\n"
          end)

        {:reply, mensagem, pessoa}
    end
  end

  defp listar_produtos_com_estoque_baixo(produtos) do
    produtos
    |> Enum.filter(fn %Produto{
                        quantidade_atual: quantidade_atual,
                        quantidade_minima: quantidade_minima
                      } ->
      quantidade_minima > quantidade_atual
    end)
  end
end
