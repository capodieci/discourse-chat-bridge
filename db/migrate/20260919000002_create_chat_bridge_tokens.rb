# frozen_string_literal: true

class CreateChatBridgeTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :chat_bridge_tokens do |t|
      t.string :token_hash, null: false
      t.integer :site_id, null: false
      t.integer :user_id, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_seen_at
      t.datetime :revoked_at
      t.datetime :created_at, null: false
    end

    add_index :chat_bridge_tokens, :token_hash, unique: true
    add_index :chat_bridge_tokens, %i[user_id site_id]
    add_index :chat_bridge_tokens, :expires_at
  end
end
