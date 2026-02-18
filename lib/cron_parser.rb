# frozen_string_literal: true

# Parses cron expressions into human-readable format
class CronParser
  # Parse a cron expression into human-readable text
  # @param cron_expression [String] Standard cron expression (e.g., "0 9 * * 1")
  # @return [String] Human-readable description
  def self.parse(cron_expression)
    new(cron_expression).to_human
  end

  def initialize(cron_expression)
    @expression = cron_expression.to_s.strip
  end

  def to_human
    parts = @expression.split(/\s+/)

    # Validate cron format (should have 5 parts for standard cron)
    return fallback if parts.length < 5

    minute = parts[0]
    hour = parts[1]
    day_of_month = parts[2]
    month = parts[3]
    day_of_week = parts[4]

    # Try to build a human-readable description
    description = build_description(minute, hour, day_of_month, month, day_of_week)
    description || fallback
  rescue StandardError => e
    fallback
  end

  private

  def build_description(minute, hour, day_of_month, month, day_of_week)
    # Check common patterns first
    if every_n_minutes?(minute) && hour == "*" && day_of_month == "*" && month == "*" && day_of_week == "*"
      return every_n_minutes_description(minute)
    end

    if minute == "0" && hour == "*" && day_of_month == "*" && month == "*" && day_of_week == "*"
      return "Every hour"
    end

    if daily?(minute, hour, day_of_month, month, day_of_week)
      return daily_description(minute, hour)
    end

    if weekly?(minute, hour, day_of_month, month, day_of_week)
      return weekly_description(minute, hour, day_of_week)
    end

    if monthly?(minute, hour, day_of_month, month, day_of_week)
      return monthly_description(minute, hour, day_of_month)
    end

    # Fallback for complex patterns
    build_complex_description(minute, hour, day_of_month, month, day_of_week)
  end

  def every_n_minutes?(minute)
    minute.start_with?("*/")
  end

  def every_n_minutes_description(minute)
    match = minute.match(/\*\/(\d+)/)
    return nil unless match

    n = match[1].to_i
    "Every #{n} minutes" if n > 1
  end

  def daily?(minute, hour, day_of_month, month, day_of_week)
    day_of_month == "*" && month == "*" && day_of_week == "*"
  end

  def daily_description(minute, hour)
    h = parse_hour(hour)
    m = parse_minute(minute)

    return nil if h.nil?

    time_str = format_time(h, m)
    "Daily at #{time_str}"
  end

  def weekly?(minute, hour, day_of_month, month, day_of_week)
    day_of_month == "*" && month == "*" && day_of_week != "*"
  end

  def weekly_description(minute, hour, day_of_week)
    h = parse_hour(hour)
    m = parse_minute(minute)
    days = parse_days(day_of_week)

    return nil if h.nil? || days.nil?

    time_str = format_time(h, m)
    days_str = format_days(days)

    "Every #{days_str} at #{time_str}"
  end

  def monthly?(minute, hour, day_of_month, month, day_of_week)
    day_of_month != "*" && month == "*" && day_of_week == "*"
  end

  def monthly_description(minute, hour, day_of_month)
    h = parse_hour(hour)
    m = parse_minute(minute)
    day = parse_day_of_month(day_of_month)

    return nil if h.nil? || day.nil?

    time_str = format_time(h, m)

    "Monthly on day #{day} at #{time_str}"
  end

  def build_complex_description(minute, hour, day_of_month, month, day_of_week)
    parts = []
    parts << "At #{format_minute(parse_minute(minute))} past hour" unless minute == "*"
    parts << "in hour #{hour}" unless hour == "*"
    parts << "on day #{day_of_month}" unless day_of_month == "*"
    parts << "in month #{month}" unless month == "*"
    parts << "on #{format_days(parse_days(day_of_week))}" unless day_of_week == "*"

    parts.any? ? parts.join(", ") : nil
  end

  def parse_minute(minute)
    minute == "*" ? nil : minute.to_i
  rescue StandardError
    nil
  end

  def parse_hour(hour)
    hour == "*" ? nil : hour.to_i
  rescue StandardError
    nil
  end

  def parse_day_of_month(day)
    day == "*" ? nil : day.to_i
  rescue StandardError
    nil
  end

  def parse_days(day_of_week)
    return nil if day_of_week == "*"

    days = day_of_week.split(",").map(&:strip).map(&:to_i)
    days.empty? ? nil : days
  rescue StandardError
    nil
  end

  def format_minute(minute)
    return "" if minute.nil? || minute.zero?

    minute.to_s.rjust(2, "0")
  end

  def format_hour(hour)
    return "" if hour.nil?

    hour.to_s.rjust(2, "0")
  end
  
  def format_time(hour, minute)
    return "" if hour.nil?
    
    h = hour.to_s.rjust(2, "0")
    m = (minute || 0).to_s.rjust(2, "0")
    "#{h}:#{m}"
  end

  def format_days(days)
    return nil if days.nil?

    day_names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    day_names_list = days.map { |d| day_names[d % 7] }.compact

    case day_names_list.length
    when 1
      day_names_list.first
    when 2..6
      day_names_list[0...-1].join(", ") + ", and " + day_names_list.last
    else
      day_names_list.join(", ")
    end
  end

  def fallback
    "Custom schedule: #{@expression}"
  end
end
