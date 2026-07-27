ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Budgeteer.Repo, :manual)

Mox.defmock(Budgeteer.AI.ClientMock, for: Budgeteer.AI.ClientBehaviour)
