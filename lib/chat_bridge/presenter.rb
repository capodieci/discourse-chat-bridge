# frozen_string_literal: true

module ChatBridge
  # Turns Discourse's internal objects into the small, stable shapes the widget
  # consumes.
  #
  # The widget deliberately never sees a Discourse serializer. Those change
  # between versions, carry far more than a chat bubble needs, and would drag
  # forum internals onto third party pages. Everything the widget receives is
  # built here, so a Discourse upgrade that reshapes a serializer breaks one file
  # rather than every embedding site.
  module Presenter
    module_function

    def base_url
      ::Discourse.base_url
    end

    def avatar_url(avatar_template, size = 48)
      return nil if avatar_template.blank?
      path = avatar_template.to_s.gsub("{size}", size.to_s)
      path.start_with?("http") ? path : "#{base_url.chomp("/")}#{path}"
    end

    def user(record)
      return nil if record.nil?
      {
        id: record.id,
        username: record.username,
        name: record.name,
        avatar_url: avatar_url(record.avatar_template),
      }
    end

    def channel(record, membership: nil)
      {
        id: record.id,
        title: channel_title(record),
        slug: record.slug,
        kind: record.direct_message_channel? ? "dm" : "category",
        status: record.status,
        last_message_id: record.last_message_id,
        unread_count: membership&.unread_count || 0,
        muted: membership&.muted || false,
      }
    end

    # A direct message channel has no name of its own, so Discourse builds a
    # title from its participants. Asking the channel for a title with no user in
    # scope gives a blank or a generic label, which is why the guardian's user is
    # passed through.
    def channel_title(record)
      return record.name if record.name.present?
      if record.direct_message_channel?
        return record.chatable&.users&.map(&:username)&.join(", ").presence || "Direct message"
      end
      record.chatable&.name.presence || "Channel"
    end

    # edited is passed in rather than derived here. Discourse decides a message
    # is edited by asking whether it has revisions, and last_editor_id cannot be
    # used as a shortcut because the model sets it to the author on every save
    # (`last_editor_id ||= user_id`), so it is always present. Asking each record
    # for its revisions would be one query per message, so the caller resolves
    # them in a single query and passes the answer down.
    def message(record, edited: false)
      {
        id: record.id,
        channel_id: record.chat_channel_id,
        thread_id: record.thread_id,
        user: user(record.user),
        html: ChatBridge::Sanitizer.clean(record.cooked, base_url: base_url),
        in_reply_to_id: record.in_reply_to_id,
        created_at: record.created_at&.iso8601,
        edited: edited,
        edited_at: edited ? record.updated_at&.iso8601 : nil,
        deleted: record.deleted_at.present?,
      }
    end

    # One query for a whole page of messages. Returns the ids that really have
    # been edited.
    def edited_ids_for(records)
      ids = Array(records).map(&:id)
      return Set.new if ids.empty?
      ::Chat::MessageRevision.where(chat_message_id: ids).distinct.pluck(:chat_message_id).to_set
    end
  end
end
