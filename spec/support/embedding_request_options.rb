# frozen_string_literal: true

# Captures the Faraday request options an embedding adapter sets for one call.
module EmbeddingRequestOptions
  def captured_request_options
    options = Faraday::RequestOptions.new
    allow(Faraday).to receive(:post) do |*, &block|
      block&.call(double("request", options: options))
      instance_double(Faraday::Response, success?: false)
    end
    yield
    options
  end
end

RSpec.configure { |config| config.include EmbeddingRequestOptions, type: :service }
