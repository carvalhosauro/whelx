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

    live "/", ChatLive, :index
    live "/contacts", ContactsLive, :index
    live "/templates", TemplatesLive, :index
    live "/config", ConfigLive, :index
    get "/ui/media/:id", UiMediaController, :show
  end

  scope "/_whelx", WhelxWeb.Control do
    pipe_through :api

    post "/seed", SystemController, :seed
    post "/reset", SystemController, :reset
    get "/config", SystemController, :config
    put "/config", SystemController, :update_config
    post "/tokens", SystemController, :create_token
    get "/chaos", SystemController, :chaos
    put "/chaos", SystemController, :update_chaos

    post "/contacts/bulk", ContactController, :bulk
    post "/contacts/:wa_id/messages", ContactController, :send_message
    post "/contacts/:wa_id/reply-interactive", ContactController, :reply_interactive
    resources "/contacts", ContactController, param: "wa_id", except: [:new, :edit]

    get "/messages", MessageController, :index
    get "/conversations/:id", MessageController, :show_conversation
    post "/conversations/:id/open", MessageController, :open
    post "/conversations/:id/expire-window", MessageController, :expire_window

    get "/templates", TemplateController, :index
    post "/templates/:id/approve", TemplateController, :approve
    post "/templates/:id/reject", TemplateController, :reject

    get "/webhooks/deliveries", WebhookController, :index
    post "/webhooks/deliveries/:id/redeliver", WebhookController, :redeliver
    post "/webhooks/verify", WebhookController, :verify
    get "/requests", WebhookController, :requests
    post "/wait", WaitController, :create
  end

  scope "/_whelx", WhelxWeb do
    pipe_through :api

    post "/mcp", McpController, :handle
    get "/mcp", McpController, :stream
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
