defmodule EstoqueDeCasaBot.TelegramClient do
  use Tesla

  @token Application.get_env(:estoque_de_casa_bot, __MODULE__)[:telegram_token]

  plug(
    Tesla.Middleware.BaseUrl,
    "https://api.telegram.org/bot#{@token}"
  )

  plug(Tesla.Middleware.JSON)

  def get_messages(update_id) do
    get("/getUpdates?timeout=100&offset=#{update_id + 1}")
    |> case do
      {:ok,
       %Tesla.Env{
         body: %{
           "ok" => true,
           "result" => result
         }
       }} ->
        {:ok, result}

      error ->
        IO.inspect(error)
        {:error, error}
    end
  end

  def send_response(chat_id, response) do
    get("/sendMessage?chat_id=#{chat_id}&text=#{response |> URI.encode_www_form()}")
  end
end
