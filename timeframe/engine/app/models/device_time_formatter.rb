# frozen_string_literal: true

class DeviceTimeFormatter
  FORMATS = %w[12h 24h].freeze

  def self.normalize(time_format)
    FORMATS.include?(time_format) ? time_format : "12h"
  end

  def self.format(value, time_format: "12h", compact: false, include_period: true, seconds: false)
    if normalize(time_format) == "24h"
      return value.strftime("%H") if compact && value.min.zero?

      return value.strftime(seconds ? "%H:%M:%S" : "%H:%M")
    end

    label = value.strftime("%-l")
    label = "#{label}:#{value.strftime(seconds ? "%M:%S" : "%M")}" if !compact || value.min.positive?
    return label unless include_period

    period = value.strftime("%P")
    compact ? "#{label}#{period[0]}" : "#{label} #{period.upcase}"
  end
end