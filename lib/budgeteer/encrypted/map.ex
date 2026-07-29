defmodule Budgeteer.Encrypted.Map do
  @moduledoc false
  use Cloak.Ecto.Map, vault: Budgeteer.Vault
end
