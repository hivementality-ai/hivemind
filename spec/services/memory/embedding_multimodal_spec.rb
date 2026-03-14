# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Memory::Embedding multimodal support", type: :service do
  let(:all_modalities) { [ :text, :image, :audio, :video, :pdf ] }

  describe ".generate_multimodal" do
    let(:text_vector) { Array.new(768) { rand } }
    let(:multimodal_vector) { Array.new(768) { rand } }

    it "falls back to text-only when adapter does not support media" do
      adapter = instance_double(Embeddings::OllamaAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: [ :text ] })
      allow(adapter).to receive(:embed_text).with("hello").and_return(text_vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal("hello", images: [ { data: "base64data", mime_type: "image/png" } ])

      expect(result[:embedding]).to eq(text_vector)
      expect(result[:modality]).to eq("text")
    end

    it "uses multimodal embedding when adapter supports images" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: all_modalities })
      allow(adapter).to receive(:embed_multimodal).and_return(multimodal_vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal(
        "a cat sitting on a mat",
        images: [ { data: "base64data", mime_type: "image/png" } ]
      )

      expect(result[:embedding]).to eq(multimodal_vector)
      expect(result[:modality]).to eq("multimodal")
    end

    it "uses multimodal embedding with audio" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: all_modalities })
      allow(adapter).to receive(:embed_multimodal).and_return(multimodal_vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal(
        "meeting notes",
        audio: [ { data: "audio_base64", mime_type: "audio/mp3" } ]
      )

      expect(result[:modality]).to eq("multimodal")
      expect(adapter).to have_received(:embed_multimodal).with(
        [ { text: "meeting notes" }, { audio: "audio_base64", mime_type: "audio/mp3" } ]
      )
    end

    it "uses multimodal embedding with video" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: all_modalities })
      allow(adapter).to receive(:embed_multimodal).and_return(multimodal_vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal(
        "tutorial clip",
        video: [ { data: "video_base64", mime_type: "video/mp4" } ]
      )

      expect(result[:modality]).to eq("multimodal")
      expect(adapter).to have_received(:embed_multimodal).with(
        [ { text: "tutorial clip" }, { video: "video_base64", mime_type: "video/mp4" } ]
      )
    end

    it "uses multimodal embedding with documents (PDF)" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: all_modalities })
      allow(adapter).to receive(:embed_multimodal).and_return(multimodal_vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal(
        "quarterly report",
        documents: [ { data: "pdf_base64", mime_type: "application/pdf" } ]
      )

      expect(result[:modality]).to eq("multimodal")
      expect(adapter).to have_received(:embed_multimodal).with(
        [ { text: "quarterly report" }, { document: "pdf_base64", mime_type: "application/pdf" } ]
      )
    end

    it "combines multiple media types in a single embedding" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: all_modalities })
      allow(adapter).to receive(:embed_multimodal).and_return(multimodal_vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal(
        "multimodal context",
        images: [ { data: "img", mime_type: "image/png" } ],
        audio: [ { data: "aud", mime_type: "audio/wav" } ]
      )

      expect(result[:modality]).to eq("multimodal")
      expect(adapter).to have_received(:embed_multimodal).with([
        { text: "multimodal context" },
        { image: "img", mime_type: "image/png" },
        { audio: "aud", mime_type: "audio/wav" }
      ])
    end

    it "ignores unsupported media types and falls back to supported ones" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      # Only supports text + image, not audio
      allow(adapter).to receive(:capabilities).and_return({ modalities: [ :text, :image ] })
      allow(adapter).to receive(:embed_multimodal).and_return(multimodal_vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal(
        "partial support",
        images: [ { data: "img", mime_type: "image/png" } ],
        audio: [ { data: "aud", mime_type: "audio/mp3" } ]
      )

      expect(result[:modality]).to eq("multimodal")
      # Only image part included, audio skipped
      expect(adapter).to have_received(:embed_multimodal).with([
        { text: "partial support" },
        { image: "img", mime_type: "image/png" }
      ])
    end

    it "falls back to text-only when no media is provided" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: all_modalities })
      allow(adapter).to receive(:embed_text).with("hello").and_return(text_vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal("hello")

      expect(result[:embedding]).to eq(text_vector)
      expect(result[:modality]).to eq("text")
    end

    it "returns nil when no adapter is available" do
      allow(Embeddings::Registry).to receive(:current).and_return(nil)

      result = Memory::Embedding.generate_multimodal("hello")
      expect(result).to be_nil
    end

    it "returns nil on error without raising" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: all_modalities })
      allow(adapter).to receive(:embed_multimodal).and_raise(StandardError, "API down")
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      result = Memory::Embedding.generate_multimodal("hello", images: [ { data: "x", mime_type: "image/png" } ])
      expect(result).to be_nil
    end
  end

  describe ".multimodal?" do
    it "returns true when adapter supports images" do
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: all_modalities })
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      expect(Memory::Embedding.multimodal?).to be true
    end

    it "returns false when adapter is text-only" do
      adapter = instance_double(Embeddings::OllamaAdapter)
      allow(adapter).to receive(:capabilities).and_return({ modalities: [ :text ] })
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      expect(Memory::Embedding.multimodal?).to be false
    end

    it "returns false when no adapter is available" do
      allow(Embeddings::Registry).to receive(:current).and_return(nil)

      expect(Memory::Embedding.multimodal?).to be false
    end
  end
end
