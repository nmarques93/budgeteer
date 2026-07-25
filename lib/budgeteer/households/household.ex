defmodule Budgeteer.Households.Household do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "households" do
    field :name, :string
    has_many :users, Budgeteer.Households.User

    timestamps(type: :utc_datetime)
  end

  def changeset(household, attrs) do
    household
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
  end
end
