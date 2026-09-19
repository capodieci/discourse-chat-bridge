# frozen_string_literal: true

class AddFeaturesToChatBridgeSites < ActiveRecord::Migration[7.0]
  def change
    # Appearance lives in `theme`. Behaviour lives here, kept separate because
    # the two are edited by different people for different reasons: a designer
    # changes a colour, an administrator decides whether a marketing site may
    # carry private messages.
    add_column :chat_bridge_sites, :features, :json
  end
end
