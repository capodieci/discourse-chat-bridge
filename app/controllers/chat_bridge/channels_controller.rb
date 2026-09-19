# frozen_string_literal: true

module ChatBridge
  class ChannelsController < ChatBridge::BaseController
    before_action :ensure_can_chat

    # The channels this visitor is already following on the forum. The site's
    # allowed_channel_ids can narrow that further, but never widen it: the list
    # starts from what Discourse says this user may see.
    def list
      rate_limit_bridge!("channels_list", 30, 1.minute)
      return if performed?

      result = ::Chat::ListUserChannels.call(guardian: bridge_guardian)
      return render_bridge_error("chat_disabled", 503) if !result.success?

      structured = result.structured
      memberships = index_memberships(structured)

      channels =
        (Array(structured[:public_channels]) + Array(structured[:direct_message_channels]))
          .select { |c| bridge_site.permits_channel?(c.id) }
          .map { |c| ChatBridge::Presenter.channel(c, membership: memberships[c.id]) }

      render_bridge_ok(channels: channels)
    end

    # A deliberately cheap change check, called often by the widget's transport.
    #
    # It answers one question only: has anything happened. Two indexed queries,
    # no serializers, no message bodies, no per channel counting. The widget
    # compares last_message_id against last_read_message_id itself and only asks
    # for actual messages when something moved. Exact unread counts come from
    # #list, which the widget calls when the panel is opened, not on a timer.
    def updates
      rate_limit_bridge!("updates", 120, 1.minute)
      return if performed?

      memberships =
        ::Chat::UserChatChannelMembership.where(user_id: bridge_user.id, following: true).pluck(
          :chat_channel_id,
          :last_read_message_id,
        )

      return render_bridge_ok(channels: []) if memberships.empty?

      last_read = memberships.to_h
      ids = last_read.keys.select { |id| bridge_site.permits_channel?(id) }

      channels =
        ::Chat::Channel
          .where(id: ids)
          .pluck(:id, :last_message_id)
          .map do |id, last_message_id|
            {
              id: id,
              last_message_id: last_message_id,
              last_read_message_id: last_read[id],
            }
          end

      render_bridge_ok(channels: channels)
    end

    def mark_read
      channel_id = params[:channel_id].to_i
      message_id = params[:message_id].presence&.to_i

      channel = authorized_channel(channel_id)
      return if channel.nil?

      ::Chat::UpdateUserChannelLastRead.call(
        params: {
          channel_id: channel.id,
          message_id: message_id || channel.last_message_id,
        },
        guardian: bridge_guardian,
      )

      render_bridge_ok(channel_id: channel.id)
    end

    private

    def index_memberships(structured)
      Array(structured[:memberships]).index_by(&:chat_channel_id)
    rescue StandardError
      {}
    end
  end
end
