# frozen_string_literal: true

class CreateChatBridgeSites < ActiveRecord::Migration[7.0]
  def change
    create_table :chat_bridge_sites do |t|
      t.string :site_key, null: false
      t.string :origin, null: false
      t.string :name, null: false
      t.integer :allowed_channel_ids, array: true
      t.json :theme
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :chat_bridge_sites, :site_key, unique: true
    add_index :chat_bridge_sites, :origin, unique: true
  end
end
