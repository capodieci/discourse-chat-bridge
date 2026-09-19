# frozen_string_literal: true

ChatBridge::Engine.routes.draw do
  # GET is used here deliberately, and only here. This endpoint is a browser
  # navigation target for the login popup, and a redirect flow cannot be a POST.
  get "/auth/start" => "auth#start"

  # Monitoring endpoint. Effectively static, so GET is appropriate.
  get "/health" => "health#show"

  # The administration page. A page, so GET.
  get "/admin" => "admin_page#show"

  # The widget itself. Served here rather than from the plugin's public
  # directory, because Discourse serves that with a one year immutable cache
  # policy, which behind a CDN means a released fix reaches nobody.
  get "/widget.js" => "asset#widget"
  get "/widget.strings.en.json" => "asset#strings"

  # Everything else is JSON in by POST, JSON out, per project convention.
  # OPTIONS is matched so cross origin preflight requests get a real answer.
  match "/api/auth/begin" => "handshake#begin_handshake", :via => %i[post options]
  match "/api/auth/claim" => "handshake#claim", :via => %i[post options]

  match "/api/session/me" => "session#me", :via => %i[post options]
  match "/api/session/logout" => "session#logout", :via => %i[post options]

  match "/api/channels/list" => "channels#list", :via => %i[post options]
  match "/api/channels/mark_read" => "channels#mark_read", :via => %i[post options]
  match "/api/channels/updates" => "channels#updates", :via => %i[post options]
  match "/api/channels/mute" => "channels#mute", :via => %i[post options]

  match "/api/messages/history" => "messages#history", :via => %i[post options]
  match "/api/messages/send" => "messages#send_message", :via => %i[post options]

  match "/api/users/search" => "users#search", :via => %i[post options]
  match "/api/dm/open" => "users#open_dm", :via => %i[post options]

  # Multipart rather than JSON, because a file has to arrive as multipart.
  match "/api/uploads/create" => "uploads#create", :via => %i[post options]
end
