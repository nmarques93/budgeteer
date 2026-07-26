defmodule BudgeteerWeb.Router do
  use BudgeteerWeb, :router

  import BudgeteerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BudgeteerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BudgeteerWeb do
    pipe_through :browser

    get "/", PageController, :home
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
      on_mount: [{BudgeteerWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/accounts", AccountLive.Index, :index
      live "/accounts/new", AccountLive.Form, :new
      live "/accounts/:id", AccountLive.Show, :show
      live "/accounts/:id/edit", AccountLive.Form, :edit

      live "/accounts/:account_id/transactions", TransactionLive.Index, :index
      live "/accounts/:account_id/transactions/new", TransactionLive.Form, :new
      live "/accounts/:account_id/transactions/:id", TransactionLive.Show, :show
      live "/accounts/:account_id/transactions/:id/edit", TransactionLive.Form, :edit

      live "/categories", CategoryLive.Index, :index
      live "/categories/new", CategoryLive.Form, :new
      live "/categories/:id", CategoryLive.Show, :show
      live "/categories/:id/edit", CategoryLive.Form, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", BudgeteerWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{BudgeteerWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
