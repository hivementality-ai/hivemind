# frozen_string_literal: true

# Shared session chat behavior used by the web, mobile, and API session
# controllers: creating a chat session for an agent, sending a message
# (including ask_user reply routing), sending interrupt signals, and
# renaming a session. Keeping this logic in one place means the three
# controllers can't drift from each other on how these actions behave.
module SessionChatActions
  extend ActiveSupport::Concern

  private

  def resolve_agent(identifier)
    Agent.by_slug(identifier).first || Agent.find_by(id: identifier)
  end

  def create_chat_session(agent:, user:)
    session = Session.create!(
      agent: agent,
      session_key: SecureRandom.uuid,
      status: :active,
      transcript: [],
      metadata: { started_by: user.id },
      last_activity_at: Time.current
    )
    Plugins::Hooks.trigger("session_created", session: session)
    session
  end

  # Returns one of :blank, :resolved_pending_question, :enqueued
  def process_chat_message(session:, message:, images: nil, files: nil)
    user_message = message&.strip
    has_attachments = images.present? || files.present?

    return :blank if user_message.blank? && !has_attachments

    result = Sessions::ResolvePendingQuestion.call(session: session, user_message: user_message)
    return :resolved_pending_question if result.success?

    attachment_ids = process_message_attachments(session: session, images: images, files: files)

    ActionCable.server.broadcast("session_#{session.id}", { type: "user_message", content: user_message })
    ChatStreamJob.perform_later(session.id, user_message.to_s, attachment_ids)
    :enqueued
  end

  def process_message_attachments(session:, images:, files:)
    attachment_ids = []

    [ images, files ].compact.each do |file_list|
      Array(file_list).each do |upload|
        next unless upload.respond_to?(:content_type)

        attachment = session.chat_attachments.create!(
          content_type: upload.content_type,
          filename: upload.original_filename,
          byte_size: upload.size
        )
        attachment.file.attach(upload)
        attachment_ids << attachment.id
      end
    end

    attachment_ids
  end

  # Returns { type: } on success or { error: } on failure.
  def send_session_interrupt(session:, type:, message:)
    signal_type = type.to_s.strip
    msg = message.to_s.strip

    unless SessionSignal::TYPES.include?(signal_type)
      return { error: "Invalid signal type. Must be: #{SessionSignal::TYPES.join(', ')}" }
    end

    if signal_type != "cancel" && msg.blank?
      return { error: "Message required for #{signal_type}" }
    end

    SessionSignal.set(session.id, type: signal_type, message: msg.presence)

    # Propagate signal to any running sub-agent child sessions
    if session.respond_to?(:sub_agent_tasks_as_parent)
      session.sub_agent_tasks_as_parent.where(status: "running").find_each do |sat|
        SessionSignal.set(sat.child_session.id, type: signal_type, message: msg.presence) if sat.child_session
      end
    end

    # Broadcast to UI immediately for visual feedback
    ActionCable.server.broadcast(
      "session_#{session.id}",
      { type: "interrupt_sent", signal_type: signal_type, message: msg.presence }
    )

    { type: signal_type }
  end

  # Returns { title: } on success or { error: } on failure.
  def rename_chat_session(session:, title:)
    new_title = title.to_s.strip

    if new_title.blank? || new_title.length > 100
      return { error: "Title must be between 1 and 100 characters" }
    end

    session.update!(title: new_title)
    ActionCable.server.broadcast("session_#{session.id}", { type: "title_update", title: new_title })
    { title: new_title }
  end
end
