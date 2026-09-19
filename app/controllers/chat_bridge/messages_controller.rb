# frozen_string_literal: true

module ChatBridge
  class MessagesController < ChatBridge::BaseController
    before_action :ensure_can_chat

    MAX_PAGE_SIZE = 50

    def history
      channel = authorized_channel(params[:channel_id].to_i)
      return if channel.nil?

      page_size = params[:limit].to_i
      page_size = 30 if page_size <= 0
      page_size = MAX_PAGE_SIZE if page_size > MAX_PAGE_SIZE

      call_params = { channel_id: channel.id, page_size: page_size }

      # before_id pages backwards through history. Discourse expresses this as a
      # target message plus a direction rather than a cursor.
      if params[:before_id].present?
        call_params[:target_message_id] = params[:before_id].to_i
        call_params[:direction] = "past"
      end

      result =
        ::Chat::ListChannelMessages.call(
          params: call_params,
          guardian: bridge_guardian,
          options: {
            max_page_size: MAX_PAGE_SIZE,
          },
        )

      return render_bridge_error("not_allowed", 403) if !result.success?

      records = Array(result.messages)
      edited = ChatBridge::Presenter.edited_ids_for(records)
      messages = records.map { |m| ChatBridge::Presenter.message(m, edited: edited.include?(m.id)) }

      render_bridge_ok(channel_id: channel.id, messages: messages)
    end

    def send_message
      rate_limit_bridge!("send", 20, 1.minute)
      return if performed?

      channel = authorized_channel(params[:channel_id].to_i)
      return if channel.nil?

      text = params[:text].to_s
      upload_ids = Array(params[:upload_ids]).map(&:to_i).reject(&:zero?).first(10)

      # A voice message has no text, so emptiness is only an error when there is
      # nothing attached either.
      if text.strip.empty? && upload_ids.empty?
        return render_bridge_error("empty_message", 422)
      end

      # Only uploads this visitor created may be attached. Without this check a
      # client could attach any upload id on the forum, including someone else's
      # private attachment, and have it rendered into a channel.
      if upload_ids.present?
        owned = ::Upload.where(id: upload_ids, user_id: bridge_user.id).pluck(:id)
        return render_bridge_error("upload_not_yours", 403) if owned.sort != upload_ids.sort
      end

      result =
        ::Chat::CreateMessage.call(
          params: {
            chat_channel_id: channel.id.to_s,
            message: text,
            upload_ids: upload_ids.presence,
            in_reply_to_id: params[:in_reply_to_id].presence&.to_s,
            thread_id: params[:thread_id].presence&.to_s,
            # Discourse deduplicates on this, so a retried send after a dropped
            # connection does not post the same line twice.
            staged_id: params[:client_nonce].presence&.to_s,
          }.compact,
          guardian: bridge_guardian,
        )

      if !result.success?
        return render_bridge_error("not_allowed", 403)
      end

      # A freshly created message has no revisions, so edited is false by
      # definition and needs no query.
      render_bridge_ok(message: ChatBridge::Presenter.message(result.message_instance, edited: false))
    end
  end
end
