# frozen_string_literal: true

class AddHandshakeToChatBridgeAuthNonces < ActiveRecord::Migration[7.0]
  def change
    # The login popup cannot always postMessage its result back. Discourse's
    # /login page carries Cross-Origin-Opener-Policy: same-origin-allow-popups,
    # which severs window.opener when the opener is a different origin, and once
    # severed it stays severed. Any visitor not already signed in to the forum
    # passes through that page, so postMessage fails for the common case.
    #
    # These columns let the widget collect its token by asking for it instead:
    # the popup marks the handshake authorised, and the widget claims it with a
    # secret that never travels in a URL.
    add_column :chat_bridge_auth_nonces, :claim_secret_hash, :string
    add_column :chat_bridge_auth_nonces, :user_id, :integer
    add_column :chat_bridge_auth_nonces, :authorized_at, :datetime

    add_index :chat_bridge_auth_nonces, :authorized_at
  end
end
