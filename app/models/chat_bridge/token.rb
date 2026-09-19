# frozen_string_literal: true

module ChatBridge
  class Token < ::ActiveRecord::Base
    self.table_name = "chat_bridge_tokens"

    belongs_to :site, class_name: "ChatBridge::Site", foreign_key: :site_id
    belongs_to :user, class_name: "::User", foreign_key: :user_id

    scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.zone.now) }

    # Issues a token for a user on a site. The plain token is returned to the
    # caller once and never stored: only its SHA256 hash goes to the database,
    # so a database leak does not hand out working sessions.
    def self.issue!(user:, site:)
      plain = SecureRandom.urlsafe_base64(32)

      record =
        create!(
          token_hash: hash_token(plain),
          site_id: site.id,
          user_id: user.id,
          expires_at: SiteSetting.chat_bridge_token_ttl_hours.to_i.hours.from_now,
          created_at: Time.zone.now,
        )

      [plain, record]
    end

    def self.hash_token(plain)
      Digest::SHA256.hexdigest(plain.to_s)
    end

    # Looks up an active token by its plain value. Returns nil for anything
    # unknown, revoked or expired, so callers only ever see a usable token.
    def self.authenticate(plain)
      return nil if plain.blank?
      active.find_by(token_hash: hash_token(plain))
    end

    def revoke!
      update!(revoked_at: Time.zone.now)
    end

    def touch_last_seen!
      # Written at most once a minute. A chat widget polls often, and there is no
      # reason to write a row on every request just to record liveness.
      return if last_seen_at.present? && last_seen_at > 1.minute.ago
      update_column(:last_seen_at, Time.zone.now)
    end

    def self.revoke_all_for_user!(user_id)
      where(user_id: user_id, revoked_at: nil).update_all(revoked_at: Time.zone.now)
    end

    def self.prune!
      where("expires_at < ?", 7.days.ago).delete_all
    end
  end
end
