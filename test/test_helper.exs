ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Budgeteer.Repo, :manual)

Mox.defmock(Budgeteer.AI.ClientMock, for: Budgeteer.AI.ClientBehaviour)
Mox.defmock(Budgeteer.RecipeUrlFetcherMock, for: Budgeteer.RecipeUrlFetcherBehaviour)
Mox.defmock(Budgeteer.AI.DeepSeekClientMock, for: Budgeteer.AI.DeepSeekClientBehaviour)
