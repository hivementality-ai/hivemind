# frozen_string_literal: true

module Agents
  class LoopDetector
    def self.analyze(tool_history:, config:)
      new(tool_history:, config:).analyze
    end

    def initialize(tool_history:, config:)
      @tool_history = tool_history
      @config = config
    end

    def analyze
      return :ok if @tool_history.empty?
      return :circuit_breaker if circuit_breaker_triggered?
      return :critical if critical_loop_detected?
      return :warning if warning_loop_detected?

      :ok
    end

    private

    def circuit_breaker_triggered?
      @tool_history.size >= @config[:circuit_breaker_threshold]
    end

    def critical_loop_detected?
      (enabled_detectors[:generic_repeat] && generic_repeat_critical?) ||
      (enabled_detectors[:ping_pong] && ping_pong_critical?) ||
      (enabled_detectors[:no_progress] && no_progress_critical?)
    end

    def warning_loop_detected?
      (enabled_detectors[:generic_repeat] && generic_repeat_warning?) ||
      (enabled_detectors[:ping_pong] && ping_pong_warning?) ||
      (enabled_detectors[:no_progress] && no_progress_warning?)
    end

    def enabled_detectors
      @config[:detectors] || {}
    end

    # Generic Repeat Detector
    def generic_repeat_critical?
      return false unless enabled_detectors[:generic_repeat]

      count_repeated_calls >= @config[:critical_threshold]
    end

    def generic_repeat_warning?
      return false unless enabled_detectors[:generic_repeat]

      count_repeated_calls >= @config[:warning_threshold]
    end

    def count_repeated_calls
      return 0 if @tool_history.empty?

      # Track frequency of tool_name + params hash combinations
      call_signatures = {}
      
      recent_history.each do |call|
        signature = call_signature(call)
        call_signatures[signature] = (call_signatures[signature] || 0) + 1
      end

      call_signatures.values.max || 0
    end

    def call_signature(call)
      {
        tool_name: call[:tool_name],
        params_hash: hash_params(call[:params] || {})
      }
    end

    def hash_params(params)
      # Create a stable hash of the parameters
      params.sort.to_h.hash
    end

    # Ping-Pong Detector
    def ping_pong_critical?
      return false unless enabled_detectors[:ping_pong]

      detect_ping_pong_pattern >= 5
    end

    def ping_pong_warning?
      return false unless enabled_detectors[:ping_pong]

      detect_ping_pong_pattern >= 3
    end

    def detect_ping_pong_pattern
      return 0 if recent_history.size < 4

      # Look for A→B→A→B patterns
      max_ping_pong = 0
      history = recent_history

      (0..history.size - 4).each do |i|
        call_a = call_signature(history[i])
        call_b = call_signature(history[i + 1])

        # Skip if A and B are the same (not a ping-pong)
        next if call_a == call_b

        consecutive_ping_pong = 1
        j = i + 2

        # Count how many A→B→A→B cycles we can find
        while j < history.size - 1
          if call_signature(history[j]) == call_a && call_signature(history[j + 1]) == call_b
            consecutive_ping_pong += 1
            j += 2
          else
            break
          end
        end

        max_ping_pong = [max_ping_pong, consecutive_ping_pong].max
      end

      max_ping_pong
    end

    # No-Progress Detector  
    def no_progress_critical?
      return false unless enabled_detectors[:no_progress]

      similar_outputs_count >= (@config[:critical_threshold] / 2)  # Half the threshold for output similarity
    end

    def no_progress_warning?
      return false unless enabled_detectors[:no_progress]

      similar_outputs_count >= (@config[:warning_threshold] / 2)  # Half the threshold for output similarity
    end

    def similar_outputs_count
      return 0 if recent_history.size < 3

      # Track output similarity (simple hash or length comparison)
      output_hashes = recent_history.last(10).map do |call|
        output = call[:output].to_s  # Convert nil to empty string
        {
          hash: output.hash,
          length: output.length,
          truncated: output.length > 100 ? output[0..99] : output  # Manual truncate to avoid nil issues
        }
      end

      return 0 if output_hashes.size < 3

      # Find the longest sequence of similar outputs at the end
      similar_count = 1
      last_output = output_hashes.last

      (output_hashes.size - 2).downto(0) do |i|
        if outputs_similar?(output_hashes[i], last_output)
          similar_count += 1
        else
          break
        end
      end

      similar_count
    end

    def outputs_similar?(output1, output2)
      # Consider outputs similar if:
      # 1. They have the same hash (identical), OR
      # 2. They have very similar length AND similar truncated content
      return true if output1[:hash] == output2[:hash]
      
      length_diff = (output1[:length] - output2[:length]).abs
      max_length = [output1[:length], output2[:length]].max
      
      # If lengths are within 10% and truncated content is similar
      if max_length > 0 && length_diff.to_f / max_length < 0.1
        similarity = string_similarity(output1[:truncated], output2[:truncated])
        similarity > 0.8
      else
        false
      end
    end

    def string_similarity(str1, str2)
      return 1.0 if str1 == str2
      return 0.0 if str1.empty? || str2.empty?

      # Simple character-based similarity
      chars1 = str1.chars
      chars2 = str2.chars
      
      common_chars = (chars1 & chars2).size
      total_chars = [chars1.size, chars2.size].max
      
      common_chars.to_f / total_chars
    end

    def recent_history
      # Return the sliding window of recent calls
      history_size = @config[:history_size] || 30
      @tool_history.last(history_size)
    end
  end
end