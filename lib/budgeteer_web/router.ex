defmodule BudgeteerWeb.Router do
  use BudgeteerWeb, :router

  import BudgeteerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BudgeteerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug BudgeteerWeb.Plugs.ContentSecurityPolicy
    plug :fetch_current_scope_for_user
    plug BudgeteerWeb.Plugs.SetLocale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :mcp do
    plug :accepts, ["json"]
    plug BudgeteerWeb.MCPAuthPlug
  end

  scope "/mcp" do
    pipe_through :mcp

    forward "/", Anubis.Server.Transport.StreamableHTTP.Plug, server: BudgeteerWeb.MCP.Server
  end

  scope "/", BudgeteerWeb do
    pipe_through :api

    get "/health/live", HealthController, :live
    get "/health/ready", HealthController, :ready
    post "/webhooks/resend-inbound", InboundEmailController, :create
  end

  scope "/", BudgeteerWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/locale/:locale", LocaleController, :set
  end

  # Other scopes may use custom stacks.
  # scope "/api", BudgeteerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:budgeteer, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BudgeteerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", BudgeteerWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {BudgeteerWeb.LocaleHook, :default},
        {BudgeteerWeb.UserAuth, :require_authenticated},
        {BudgeteerWeb.PresenceHooks, :track}
      ] do
      live "/dashboard", DashboardLive, :index

      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/accounts", AccountLive.Index, :index
      live "/accounts/new", AccountLive.Form, :new
      live "/accounts/:id", AccountLive.Show, :show
      live "/accounts/:id/edit", AccountLive.Form, :edit

      live "/transactions", TransactionLive.Search, :index

      live "/accounts/:account_id/transactions", TransactionLive.Index, :index
      live "/accounts/:account_id/transactions/new", TransactionLive.Form, :new
      live "/accounts/:account_id/transactions/:id", TransactionLive.Show, :show
      live "/accounts/:account_id/transactions/:id/edit", TransactionLive.Form, :edit

      live "/accounts/:account_id/statements", StatementLive.Index, :index
      live "/accounts/:account_id/statements/new", StatementLive.Upload, :new
      live "/accounts/:account_id/statements/:id/review", StatementLive.Review, :edit

      live "/categories", CategoryLive.Index, :index
      live "/categories/new", CategoryLive.Form, :new
      live "/categories/:id", CategoryLive.Show, :show
      live "/categories/:id/edit", CategoryLive.Form, :edit

      live "/groceries", GroceryListLive.Index, :index
      live "/groceries/new", GroceryListLive.Form, :new
      live "/groceries/:id", GroceryListLive.Show, :show
      live "/groceries/:id/edit", GroceryListLive.Form, :edit

      live "/recipes", RecipeLive.Index, :index
      live "/recipes/new", RecipeLive.Form, :new
      live "/recipes/extract", RecipeLive.Extract, :new
      live "/recipes/:id", RecipeLive.Show, :show
      live "/recipes/:id/edit", RecipeLive.Form, :edit

      live "/meal-plan", MealPlanLive.Index, :index

      live "/subscriptions", SubscriptionLive.Index, :index

      live "/calendar", CalendarLive.Index, :index
      live "/calendar/new", CalendarLive.Form, :new
      live "/calendar/:id/edit", CalendarLive.Form, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
    get "/users/settings/google-calendar/connect", GoogleCalendarController, :connect
    get "/users/settings/google-calendar/callback", GoogleCalendarController, :callback
    post "/accounts/:account_id/statements", StatementController, :create
    get "/transactions/export", TransactionExportController, :download
    post "/push-tokens", PushTokenController, :create
    post "/recipes/:id/image", RecipeImageController, :create
    get "/recipes/:id/image", RecipeImageController, :show
  end

  scope "/", BudgeteerWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [
        {BudgeteerWeb.LocaleHook, :default},
        {BudgeteerWeb.UserAuth, :mount_current_scope}
      ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete

    get "/auth/:provider", UserOAuthController, :request
    get "/auth/:provider/callback", UserOAuthController, :callback
  end
end
