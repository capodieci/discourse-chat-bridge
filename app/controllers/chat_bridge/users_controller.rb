# frozen_string_literal: true

module ChatBridge
  # Finding people, and opening a conversation with them.
  class UsersController < ChatBridge::BaseController
    before_action :ensure_can_chat

    # Searches through Discourse's own chat search service, with the visitor's
    # guardian, so the results are exactly the people that visitor is allowed to
    # see. The bridge never touches the user table itself, which means it cannot
    # accidentally become a way to enumerate the membership.
    def search
      rate_limit_bridge!("user_search", 60, 1.minute)
      return if performed?

      return render_bridge_error("dm_not_available", 403) if !dm_available?

      term = params[:term].to_s.strip

      result =
        ::Chat::SearchChatable.call(
          params: {
            term: term,
            include_users: true,
            include_groups: false,
            include_category_channels: false,
            include_direct_message_channels: false,
          },
          guardian: bridge_guardian,
        )

      return render_bridge_error("not_allowed", 403) if !result.success?

      users =
        Array(result.users)
          .reject { |u| u.id == bridge_user.id }
          .first(20)
          .map { |u| ChatBridge::Presenter.user(u) }

      render_bridge_ok(users: users)
    end

    # Opens a conversation, or returns the existing one. upsert is what makes
    # asking twice idempotent: without it a second attempt creates a duplicate
    # channel and the visitor ends up with two threads to the same person.
    def open_dm
      rate_limit_bridge!("dm_open", 20, 1.minute)
      return if performed?

      return render_bridge_error("dm_not_available", 403) if !dm_available?

      usernames = Array(params[:usernames]).map { |u| u.to_s.strip }.reject(&:empty?).first(20)
      return render_bridge_error("no_recipients", 422) if usernames.empty?

      result =
        ::Chat::CreateDirectMessageChannel.call(
          params: {
            target_usernames: usernames,
            upsert: true,
          },
          guardian: bridge_guardian,
        )

      if !result.success?
        return render_bridge_error("dm_refused", 422)
      end

      channel = result.channel
      render_bridge_ok(channel: ChatBridge::Presenter.channel(channel, viewer: bridge_user))
    end

    private

    # Two independent reasons a site may not have direct messages: the
    # administrator turned them off, or the site is pinned to specific channels.
    # A DM channel is created on demand, so it can never appear in an allow list
    # written in advance, and silently permitting it would widen a configuration
    # that was deliberately narrowed.
    def dm_available?
      bridge_site.feature?("direct_messages") && bridge_site.allowed_channel_ids.blank?
    end
  end
end
