# frozen_string_literal: true

ChatBridge::Engine.routes.draw do
  # GET is used here deliberately, and only here. This endpoint is a browser
  # navigation target for the login popup, and a redirect flow cannot be a POST.
  get "/auth/start" => "auth#start"

  # Monitoring endpoint. Effectively static, so GET is appropriate.
  get "/health" => "health#show"

  # Everything else is JSON in by POST, JSON out, per project convention.
  # OPTIONS is matched so cross origin preflight requests get a real answer.
  match "/api/session/me" => "session#me", :via => %i[post options]
  match "/api/session/logout" => "session#logout", :via => %i[post options]
end
