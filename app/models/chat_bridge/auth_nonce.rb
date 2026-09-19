# frozen_string_literal: true

module ChatBridge
  class AuthNonce < ::ActiveRecord::Base
    self.table_name = "chat_bridge_auth_nonces"
    self.primary_key = "nonce"

    belongs_to :site, class_name: "ChatBridge::Site", foreign_key: :site_id

    # Binds one login popup to the one widget request that opened it, so a login
    # cannot be replayed and a token cannot be delivered to a window that did not
    # ask for it.
    def self.issue!(site:, state:)
      create!(
        nonce: SecureRandom.urlsafe_base64(24),
        site_id: site.id,
        state: state.to_s.first(128),
        created_at: Time.zone.now,
      )
    end

    # Consumes a nonce. Returns the record on success and nil on any failure,
    # including reuse and expiry. Wrapped in a transaction with a row lock so two
    # simultaneous callbacks cannot both succeed.
    def self.consume!(nonce)
      return nil if nonce.blank?

      transaction do
        record = lock.find_by(nonce: nonce)
        return nil if record.nil?
        return nil if record.used_at.present?

        if record.created_at < SiteSetting.chat_bridge_nonce_ttl_seconds.to_i.seconds.ago
          return nil
        end

        record.update!(used_at: Time.zone.now)
        record
      end
    end

    def self.prune!
      where("created_at < ?", 1.day.ago).delete_all
    end
  end
end
