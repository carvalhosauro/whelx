defmodule WhelxWeb.Router do
  use WhelxWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WhelxWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :graph do
    plug :put_format, "json"
    plug WhelxWeb.Plugs.GraphRequestLogger
    plug WhelxWeb.Plugs.GraphVersion
    plug WhelxWeb.Plugs.GraphAuth
    plug WhelxWeb.Plugs.GraphChaos
  end

  scope "/", WhelxWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Fake Graph API. Must stay last: `/:version/...` would shadow other routes.
  scope "/", WhelxWeb.Graph do
    pipe_through :graph

    get "/_media/:media_id", MediaController, :download
    get "/:version/:id", ObjectController, :show
    post "/:version/:id", ObjectController, :create
    get "/:version/:id/phone_numbers", WabaController, :phone_numbers
    post "/:version/:id/subscribed_apps", WabaController, :subscribe
    delete "/:version/:id/subscribed_apps", WabaController, :unsubscribe
    post "/:version/:id/messages", MessageController, :create
    post "/:version/:id/uploads", UploadController, :create
    get "/:version/:id/message_templates", TemplateController, :index
    post "/:version/:id/message_templates", TemplateController, :create
    delete "/:version/:id/message_templates", TemplateController, :delete

    match :*, "/:version/*rest", ObjectController, :unsupported
  end
end
