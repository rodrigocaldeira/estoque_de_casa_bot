defmodule EstoqueDeCasaBot.Bot do
  use GenServer

  alias EstoqueDeCasaBot.TelegramClient
  alias EstoqueDeCasaBot.Pessoa

  @impl true
  def init(state) do
    schedule_update()

    {:ok, state}
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{update_id: 0})
  end

  @impl true
  def handle_info(:get_messages, %{update_id: update_id} = state) do
    {:ok, messages} =
      update_id
      |> TelegramClient.get_messages()

    messages
    |> Enum.each(fn message ->
      id = get_id(message)
      text = get_text(message)
      IO.inspect(message)
      IO.inspect(text)

      pid =
        Pessoa.get_by(%{id: id})
        |> case do
          nil ->
            chat_id = get_chat_id(message)
            nome = get_nome(message)
            pessoa_pid = Pessoa.new(%{id: id, chat_id: chat_id, nome: nome})
            Pessoa.enviar_mensagem(pessoa_pid, "Olá #{nome}")
            pessoa_pid

          pessoa_pid ->
            pessoa_pid
        end

      spawn(fn -> processar_mensagem(pid, text) end)
    end)

    new_state =
      messages
      |> get_last_update_id()
      |> case do
        {:ok, last_update_id} ->
          %{state | update_id: last_update_id}

        :error ->
          state
      end

    schedule_update()
    {:noreply, new_state}
  end

  defp processar_mensagem(pessoa_pid, "/produtos") do
    Pessoa.listar_produtos(pessoa_pid)
  end

  defp processar_mensagem(pessoa_pid, "/cadastrar") do
    Pessoa.iniciar_cadastro_de_produto(pessoa_pid)
  end

  defp processar_mensagem(pessoa_pid, mensagem) do
    Pessoa.get_estado_atual(pessoa_pid)
    |> case do
      :cadastrando_produto ->
        Pessoa.salvar_nome_novo_produto(pessoa_pid, mensagem)

      :cadastrando_quantidade_atual ->
        Pessoa.salvar_quantidade_atual_novo_produto(pessoa_pid, mensagem)

      :cadastrando_quantidade_minima ->
        Pessoa.salvar_quantidade_minima_novo_produto(pessoa_pid, mensagem)

      _ ->
        Pessoa.enviar_mensagem(
          pessoa_pid,
          "Desculpe, mas não sei o que \"#{mensagem}\" significa."
        )
    end
  end

  defp schedule_update() do
    Process.send_after(self(), :get_messages, 1000)
  end

  defp get_last_update_id(messages) do
    messages
    |> Enum.take(-1)
    |> get_update_id()
  end

  defp get_update_id([%{"update_id" => update_id}]), do: {:ok, update_id}
  defp get_update_id(_), do: :error

  defp get_chat_id(%{"message" => %{"chat" => %{"id" => chat_id}}}), do: chat_id
  defp get_id(%{"message" => %{"from" => %{"id" => id}}}), do: id
  defp get_nome(%{"message" => %{"from" => %{"first_name" => nome}}}), do: nome

  defp get_text(%{"message" => %{"text" => text}}), do: text
end
