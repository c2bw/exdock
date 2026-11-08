defmodule ExdockWeb.Router do
  use ExdockWeb, :router
  import ExdockWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExdockWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ExdockWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{ExdockWeb.UserAuth, :ensure_authenticated}] do
      live "/", HomepageLive.Index, :index
      live "/images", ImagesLive.Index
      live "/releases", ReleasesLive.Index
      live "/releases/:repository_url", ReleasesLive.Index
      live "/automation", Automation.Index
      live "/priorities", ContainersPriorities.Index
      live "/containers/:node_id", ContainersLive.Index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ExdockWeb do
  #   pipe_through :api
  # end

  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  import Phoenix.LiveDashboard.Router

  scope "/dev" do
    pipe_through [:browser, :require_authenticated_user]

    live_dashboard "/dashboard", metrics: ExdockWeb.Telemetry
  end

  ## Authentication routes

  scope "/", ExdockWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
  end

  scope "/", ExdockWeb do
    pipe_through [:browser]
    delete "/users/log_out", UserSessionController, :delete
  end
end
