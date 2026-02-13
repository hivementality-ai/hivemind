# frozen_string_literal: true

module Tools
  class BaseExecutor
    def initialize(input:, config: {}, agent: nil)
      @input = input
      @config = config
      @agent = agent
    end

    def call
      raise NotImplementedError, "#{self.class}#call must be implemented"
    end

    private

    attr_reader :input, :config, :agent
  end
end
