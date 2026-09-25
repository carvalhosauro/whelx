defmodule Whelx.Contacts.Names do
  @moduledoc "Brazilian names for generated contacts."

  @first ~w(Ana Bruno Carla Diego Eduarda Felipe Gabriela Henrique Isabela João Larissa Lucas Mariana Mateus Natália Otávio Paula Rafael Sofia Thiago Vitória)
  @last ~w(Silva Santos Oliveira Souza Lima Pereira Costa Ferreira Almeida Ribeiro Carvalho Gomes Martins Rocha)

  @spec random() :: String.t()
  def random, do: Enum.random(@first) <> " " <> Enum.random(@last)
end
