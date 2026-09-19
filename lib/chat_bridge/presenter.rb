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

    # tracking is one entry from Chat::TrackingStateReport#channel_tracking,
    # which is where Discourse actually keeps unread counts. They are not on the
    # membership record: that holds last_read_message_id, and the count is
    # derived from it elsewhere.
    def channel(record, membership: nil, tracking: nil, viewer: nil)
      {
        id: record.id,
        title: channel_title(record, viewer: viewer),
        slug: record.slug,
        kind: record.direct_message_channel? ? "dm" : "category",
        status: record.status,
        last_message_id: record.last_message_id,
        unread_count: tracking_value(tracking, :unread_count),
        mention_count: tracking_value(tracking, :mention_count),
        muted: membership&.muted || false,
      }
    end

    # The tracking report hands back symbol keyed hashes, but the same data
    # arrives string keyed once it has been through as_json, so both are read.
    def tracking_value(tracking, key)
      return 0 if tracking.nil?
      (tracking[key] || tracking[key.to_s] || 0).to_i
    end

    # A direct message channel has no name of its own, so it is titled by who is
    # in it. The viewer is left out: a conversation labelled with your own name
    # alongside the other person's reads as though you are talking to yourself,
    # and in a list of several DMs the repeated name is pure noise.
    def channel_title(record, viewer: nil)
      return record.name if record.name.present?

      if record.direct_message_channel?
        names =
          Array(record.chatable&.users)
            .reject { |u| viewer && u.id == viewer.id }
            .map(&:username)

        # A note to self is a real thing in Discourse chat, so falling back to
        # the viewer's own name is correct rather than a bug.
        names = Array(record.chatable&.users).map(&:username) if names.empty?
        return names.join(", ").presence || "Direct message"
      end

      record.chatable&.name.presence || "Channel"
    end

    # edited is passed in rather than derived here. Discourse decides a message
    # is edited by asking whether it has revisions, and last_editor_id cannot be
    # used as a shortcut because the model sets it to the author on every save
    # (`last_editor_id ||= user_id`), so it is always present. Asking each record
    # for its revisions would be one query per message, so the caller resolves
    # them in a single query and passes the answer down.
    # Discourse chat does not put attachments in cooked HTML. A message that is
    # only a voice recording has an empty cooked string and its file hanging off
    # the uploads association, so a presenter that reads cooked alone renders
    # nothing at all. Attachments are therefore passed through as data and the
    # widget builds the player, which also means we are not depending on
    # whatever markup a future Discourse decides to generate.
    def upload(record)
      extension = record.extension.to_s.downcase
      kind =
        if ::FileHelper.supported_audio.include?(extension) || extension == "webm"
          "audio"
        elsif ::FileHelper.is_supported_image?(record.original_filename.to_s)
          "image"
        else
          "file"
        end

      {
        id: record.id,
        url: ::UrlHelper.absolute(record.url),
        filename: record.original_filename,
        extension: extension,
        filesize: record.filesize,
        kind: kind,
      }
    end

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
        uploads: Array(record.uploads).map { |u| upload(u) },
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
