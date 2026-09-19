# frozen_string_literal: true

module ChatBridge
  # One login attempt.
  #
  # The widget starts a handshake, receives an id and a secret, and opens the
  # popup with only the id in the URL. When the visitor is recognised, the popup
  # marks the handshake authorised against their user id. The widget then claims
  # the result by presenting the id together with the secret it kept in memory.
  #
  # The secret never appears in a URL, so the popup's address bar, browser
  # history and any referrer leak the id alone, which is useless on its own. The
  # bridge token is minted at claim time rather than stored here, so no usable
  # credential ever sits in this table.
  class AuthNonce < ::ActiveRecord::Base
    self.table_name = "chat_bridge_auth_nonces"
    self.primary_key = "nonce"

    belongs_to :site, class_name: "ChatBridge::Site", foreign_key: :site_id

    def self.begin!(site:, state:)
      secret = SecureRandom.urlsafe_base64(32)

      record =
        create!(
          nonce: SecureRandom.urlsafe_base64(24),
          site_id: site.id,
          state: state.to_s.first(128),
          claim_secret_hash: hash_secret(secret),
          created_at: Time.zone.now,
        )

      [record, secret]
    end

    def self.hash_secret(secret)
      Digest::SHA256.hexdigest(secret.to_s)
    end

    def self.ttl
      SiteSetting.chat_bridge_nonce_ttl_seconds.to_i.seconds
    end

    def fresh?
      created_at.present? && created_at > self.class.ttl.ago
    end

    # Called by the popup once Discourse has told us who the visitor is. Records
    # the user but issues nothing: the token is minted when the widget claims it.
    def self.authorize!(nonce, user_id)
      transaction do
        record = lock.find_by(nonce: nonce)
        return nil if record.nil?
        return nil if record.used_at.present?
        return nil if !record.fresh?

        record.update!(user_id: user_id, authorized_at: Time.zone.now)
        record
      end
    end

    # Called by the widget, polling. Returns the record exactly once, and only to
    # a caller that knows the secret. Comparison is constant time so the secret
    # cannot be recovered by timing the responses.
    def self.claim!(nonce, secret)
      transaction do
        record = lock.find_by(nonce: nonce)
        return nil if record.nil?
        return nil if record.used_at.present?
        return nil if !record.fresh?
        return nil if record.claim_secret_hash.blank?
        return nil if !ActiveSupport::SecurityUtils.secure_compare(
             record.claim_secret_hash,
             hash_secret(secret),
           )

        # Not authorised yet is not a failure. The visitor is still signing in,
        # and the widget should keep polling, so this is reported separately from
        # a bad id or a bad secret.
        next :pending if record.authorized_at.nil? || record.user_id.nil?

        record.update!(used_at: Time.zone.now)
        record
      end
    end

    def self.prune!
      where("created_at < ?", 1.day.ago).delete_all
    end
  end
end
