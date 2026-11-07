# frozen_string_literal: true

FactoryBot.define do
  factory :audio_note do
    association :session
    agent { session.agent }
    filename { "standup.mp3" }
    content_type { "audio/mpeg" }
    byte_size { 12 }
    status { "queued" }
    keep_recording { false }

    after(:build) do |note|
      note.file.attach(io: StringIO.new("fake audio"), filename: note.filename, content_type: note.content_type)
    end
  end
end
