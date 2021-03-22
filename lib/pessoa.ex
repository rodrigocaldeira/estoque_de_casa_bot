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

  def dar_boas_vindas(pessoa_pid) do
    {:ok, mensagem} = GenServer.call(pessoa_pid, :dar_boas_vindas)

    enviar_mensagem(pessoa_pid, mensagem)
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

  def iniciar_alteracao_de_produto(pessoa_pid) do
    GenServer.call(pessoa_pid, :listar_produtos)
    |> case do
      [] ->
        enviar_mensagem(pessoa_pid, "Você não tem nenhum produto ainda.")

      produtos ->
        mensagem =
          produtos
          |> Enum.reduce(
            "Qual produto você deseja alterar? (digite o nome produto)\n\n",
            fn produto, mensagem ->
              mensagem <>
                "#{produto.nome}, com #{produto.quantidade_atual}, mímino de #{
                  produto.quantidade_minima
                }\n"
            end
          )

        GenServer.call(pessoa_pid, :iniciar_alteracao_de_produto)

        enviar_mensagem(pessoa_pid, mensagem)
    end
  end

  def selecionar_produto_para_alterar(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:selecionar_produto_para_alterar, mensagem})
    |> case do
      :ok ->
        enviar_mensagem(
          pessoa_pid,
          "OK! O que você deseja alterar no produto #{mensagem} (informe a opção)?\n\n1 - Quantidade atual\n2 - Quantidade mímima"
        )

      :produto_inexistente ->
        enviar_mensagem(
          pessoa_pid,
          "Desculpe, mas você não tem #{mensagem} na sua lista de produtos\n\nVamos de novo\n\n"
        )

        iniciar_alteracao_de_produto(pessoa_pid)
    end
  end

  def selecionar_opcao_de_alteracao(pessoa_pid, "1") do
    {:ok, %Produto{nome: nome}} = GenServer.call(pessoa_pid, :alterando_quantidade_atual)

    enviar_mensagem(
      pessoa_pid,
      "Entendi! E qual é a quantidade atual do produto #{nome}"
    )
  end

  def selecionar_opcao_de_alteracao(pessoa_pid, "2") do
    {:ok, %Produto{nome: nome}} = GenServer.call(pessoa_pid, :alterando_quantidade_minima)

    enviar_mensagem(
      pessoa_pid,
      "Certo! E qual é a nova quantidade mínima do produto #{nome}"
    )
  end

  def selecionar_opcao_de_alteracao(pessoa_pid, _mensagem) do
    enviar_mensagem(
      pessoa_pid,
      "Opção inválida! Vamos novamente?\n\n1 - Quantidade atual\n2 - Quantidade mímina"
    )
  end

  def alterar_quantidade_atual(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:alterar_quantidade_atual, mensagem})
    |> case do
      :ok ->
        enviar_mensagem(
          pessoa_pid,
          "Quantidade atual alterada com sucesso!"
        )

      :argument_error ->
        enviar_mensagem(
          pessoa_pid,
          "Descupe, mas #{mensagem} é uma quantidade inválida! Vamos tentar novamente?\nQual é a quantidade atual deste produto?"
        )
    end
  end

  def alterar_quantidade_minima(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:alterar_quantidade_minima, mensagem})
    |> case do
      :ok ->
        enviar_mensagem(
          pessoa_pid,
          "Quantidade mínima alterada com sucesso!"
        )

      :argument_error ->
        enviar_mensagem(
          pessoa_pid,
          "Descupe, mas #{mensagem} é uma quantidade inválida! Vamos tentar novamente?\nQual é a nova quantidade mínima deste produto?"
        )
    end
  end

  def iniciar_exclusao_de_produto(pessoa_pid) do
    GenServer.call(pessoa_pid, :listar_produtos)
    |> case do
      [] ->
        enviar_mensagem(pessoa_pid, "Você não tem nenhum produto ainda.")

      produtos ->
        mensagem =
          produtos
          |> Enum.reduce(
            "Qual produto você deseja excluir? (digite o nome produto)\n\n",
            fn produto, mensagem ->
              mensagem <>
                "#{produto.nome}, com #{produto.quantidade_atual}, mímino de #{
                  produto.quantidade_minima
                }\n"
            end
          )

        GenServer.call(pessoa_pid, :iniciar_exclusao_de_produto)

        enviar_mensagem(pessoa_pid, mensagem)
    end
  end

  def selecionar_produto_para_excluir(pessoa_pid, mensagem) do
    GenServer.call(pessoa_pid, {:selecionar_produto_para_excluir, mensagem})
    |> case do
      :ok ->
        enviar_mensagem(
          pessoa_pid,
          "Você quer mesmo excluir o produto #{mensagem}?"
        )

      :produto_inexistente ->
        enviar_mensagem(
          pessoa_pid,
          "Desculpe, mas você não tem #{mensagem} na sua lista de produtos\n\nVamos de novo\n\n"
        )

        iniciar_exclusao_de_produto(pessoa_pid)
    end
  end

  def confirmar_exclusao_de_produto(pessoa_pid, mensagem) do
    mensagem
    |> String.trim()
    |> String.downcase()
    |> case do
      sim when sim in ["s", "sim"] ->
        GenServer.call(pessoa_pid, :excluir_produto)

        enviar_mensagem(
          pessoa_pid,
          "Produto excluido com sucesso!"
        )

      _ ->
        GenServer.call(pessoa_pid, :cancelar_operacao_atual)

        enviar_mensagem(
          pessoa_pid,
          "Exclusão cancelada!"
        )
    end
  end

  @impl true
  def handle_cast({:enviar_mensagem, message}, %Pessoa{chat_id: chat_id} = pessoa) do
    TelegramClient.send_response(chat_id, message)
    {:noreply, pessoa}
  end

  @impl true
  def handle_call(:dar_boas_vindas, _from, %Pessoa{nome: nome} = pessoa) do
    mensagem = """
    Olá #{nome}! Sou o seu bot de estoque!
    Estou aqui para te ajudar a controlar o estoque da sua casa!

    Para isso, eu tenho uma lista de comandos que você pode usar:

    /cadastrar - Cadastra um novo produto
    /produtos - Lista os seus produtos já cadastrados
    /alterar - Altera algum produto cadastrado
    /excluir - Exclui um produto
    /listadecompras - Monta uma nova lista de compras
    /cancelar - Cancela qualquer comando que estiver sendo executado
    /ajuda - Esta mensagem aqui!

    """

    {:reply, {:ok, mensagem}, pessoa}
  end

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
        {:reply, "Você não tem nenhum produto que precise ser comprado agora!", pessoa}

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

  def handle_call(:iniciar_alteracao_de_produto, _from, %Pessoa{} = pessoa) do
    {:reply, :ok, %{pessoa | estado_atual: :selecionando_produto_para_alterar}}
  end

  def handle_call(
        {:selecionar_produto_para_alterar, mensagem},
        _from,
        %Pessoa{produtos: produtos} = pessoa
      ) do
    nome_produto = mensagem |> String.trim()

    produtos
    |> Enum.find(fn produto -> produto.nome == nome_produto end)
    |> case do
      nil ->
        {:reply, :produto_inexistente, pessoa}

      produto ->
        {:reply, :ok,
         %{pessoa | novo_produto: produto, estado_atual: :selecionando_opcao_de_alteracao}}
    end
  end

  def handle_call(:alterando_quantidade_atual, _from, %Pessoa{novo_produto: produto} = pessoa) do
    {:reply, {:ok, produto}, %{pessoa | estado_atual: :alterando_quantidade_atual}}
  end

  def handle_call(:alterando_quantidade_minima, _from, %Pessoa{novo_produto: produto} = pessoa) do
    {:reply, {:ok, produto}, %{pessoa | estado_atual: :alterando_quantidade_minima}}
  end

  def handle_call(
        {:alterar_quantidade_atual, mensagem},
        _from,
        %Pessoa{
          novo_produto: %Produto{nome: nome},
          produtos: produtos
        } = pessoa
      ) do
    try do
      index_produto = produtos |> Enum.find_index(fn produto -> produto.nome == nome end)

      nova_lista_de_produtos =
        produtos
        |> List.update_at(index_produto, fn produto ->
          %{produto | quantidade_atual: mensagem |> String.to_integer()}
        end)

      {:reply, :ok,
       %Pessoa{
         pessoa
         | estado_atual: :esperando,
           novo_produto: %Produto{},
           produtos: nova_lista_de_produtos
       }}
    rescue
      ArgumentError ->
        {:reply, :argument_error, pessoa}
    end
  end

  def handle_call(
        {:alterar_quantidade_minima, mensagem},
        _from,
        %Pessoa{
          novo_produto: %Produto{nome: nome},
          produtos: produtos
        } = pessoa
      ) do
    try do
      index_produto = produtos |> Enum.find_index(fn produto -> produto.nome == nome end)

      nova_lista_de_produtos =
        produtos
        |> List.update_at(index_produto, fn produto ->
          %{produto | quantidade_minima: mensagem |> String.to_integer()}
        end)

      {:reply, :ok,
       %Pessoa{
         pessoa
         | estado_atual: :esperando,
           novo_produto: %Produto{},
           produtos: nova_lista_de_produtos
       }}
    rescue
      ArgumentError ->
        {:reply, :argument_error, pessoa}
    end
  end

  def handle_call(:iniciar_exclusao_de_produto, _from, %Pessoa{} = pessoa) do
    {:reply, :ok, %{pessoa | estado_atual: :selecionando_produto_para_excluir}}
  end

  def handle_call(
        {:selecionar_produto_para_excluir, mensagem},
        _from,
        %Pessoa{produtos: produtos} = pessoa
      ) do
    nome_produto = mensagem |> String.trim()

    produtos
    |> Enum.find(fn produto -> produto.nome == nome_produto end)
    |> case do
      nil ->
        {:reply, :produto_inexistente, pessoa}

      produto ->
        {:reply, :ok,
         %{pessoa | novo_produto: produto, estado_atual: :confirmando_exclusao_de_produto}}
    end
  end

  def handle_call(
        :excluir_produto,
        _from,
        %Pessoa{
          novo_produto: %Produto{nome: nome},
          produtos: produtos
        } = pessoa
      ) do
    produto_excluido =
      produtos
      |> Enum.find(fn produto -> produto.nome == nome end)

    nova_lista_de_produtos =
      produtos
      |> List.delete(produto_excluido)

    {:reply, :ok,
     %Pessoa{
       pessoa
       | novo_produto: %Produto{},
         produtos: nova_lista_de_produtos,
         estado_atual: :esperando
     }}
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
