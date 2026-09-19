# frozen_string_literal: true

module ChatBridge
  # Accepts a recorded voice message and hands it to Discourse's own upload
  # pipeline, as the visitor.
  #
  # This is the one endpoint that is not JSON in, because a file has to arrive as
  # multipart. Everything else about it is the same: bearer token, origin bound,
  # rate limited.
  #
  # Uploads go through UploadCreator rather than an HTTP call to the forum's own
  # upload endpoint. Running inside Discourse means the file never leaves the
  # process, and the visitor's own quota, extension policy and size limits apply
  # exactly as they would in the forum.
  class UploadsController < ChatBridge::BaseController
    before_action :ensure_can_chat

    # Formats a browser can actually record in. Ordered by preference in the
    # widget, but validated here too, because a client can send anything.
    #
    # m4a and ogg are in Discourse's own FileHelper.supported_audio, so the forum
    # renders them as a player. webm is not, so it arrives as a plain attachment
    # for forum users even though the widget can still play it. The widget
    # therefore prefers m4a and ogg, and webm is only a last resort.
    ALLOWED_AUDIO = {
      "audio/mp4" => "m4a",
      "audio/m4a" => "m4a",
      "audio/aac" => "m4a",
      "audio/ogg" => "ogg",
      "audio/opus" => "ogg",
      "audio/webm" => "webm",
      "audio/mpeg" => "mp3",
    }.freeze

    MAX_SECONDS = 300

    def create
      rate_limit_bridge!("upload", 30, 1.minute)
      return if performed?

      file = params[:file]
      return render_bridge_error("upload_missing", 422) if file.blank? || !file.respond_to?(:tempfile)

      mime = file.content_type.to_s.split(";").first.to_s.downcase.strip
      extension = ALLOWED_AUDIO[mime]
      return render_bridge_error("upload_type", 415) if extension.nil?

      max_bytes = SiteSetting.max_attachment_size_kb.to_i * 1024
      return render_bridge_error("upload_too_large", 413) if file.tempfile.size > max_bytes
      return render_bridge_error("upload_missing", 422) if file.tempfile.size.zero?

      filename = "voice-message-#{Time.zone.now.strftime("%Y%m%d-%H%M%S")}.#{extension}"

      upload =
        UploadCreator.new(
          file.tempfile,
          filename,
          type: "chat-composer",
          # Discourse decides what the content type really is from the bytes.
          # Trusting the browser's declared type here would let a client label
          # anything as audio.
          skip_validations: false,
        ).create_for(bridge_user.id)

      if upload.nil? || upload.errors.present?
        message = upload&.errors&.full_messages&.join(", ").presence
        return render_bridge_error("upload_rejected", 422, detail: message)
      end

      render_bridge_ok(
        upload: {
          id: upload.id,
          url: ::UrlHelper.absolute(upload.url),
          extension: upload.extension,
          filesize: upload.filesize,
          original_filename: upload.original_filename,
          playable_in_forum: ::FileHelper.supported_audio.include?(upload.extension.to_s.downcase),
        },
      )
    end
  end
end
