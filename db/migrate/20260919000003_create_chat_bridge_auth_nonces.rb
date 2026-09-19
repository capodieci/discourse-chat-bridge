# frozen_string_literal: true

class CreateChatBridgeAuthNonces < ActiveRecord::Migration[7.0]
  def change
    create_table :chat_bridge_auth_nonces, id: false do |t|
      t.string :nonce, null: false, primary_key: true
      t.integer :site_id, null: false
      t.string :state, null: false
      t.datetime :used_at
      t.datetime :created_at, null: false
    end

    add_index :chat_bridge_auth_nonces, :nonce, unique: true
    add_index :chat_bridge_auth_nonces, :created_at
  end
end
