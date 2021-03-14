defmodule EstoqueDeCasaBotTest do
  use ExUnit.Case
  doctest EstoqueDeCasaBot

  test "greets the world" do
    assert EstoqueDeCasaBot.hello() == :world
  end
end
