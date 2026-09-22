# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3

module Support

# Forgiving scalar coercion helpers shared by filtering, grouped-index
# detection, and loose configuration parsing.
#
# Structure: callers can ask for one specific scalar family without
# committing the whole pipeline to one feature's semantics.
module LooseScalar
	# Captures the supported ISO-shaped date/time profile without exposing
	# callers to Ruby's permissive and time-dependent `DateTime.parse` rules.
	# Date separators repeat independently of the time separator, which also
	# repeats inside a numeric timezone offset.
	DATETIME_STRING_PATTERN = %r{
		\A
		(?<year>\d{4})
		(?<date_separator>[:.\/-])
		(?<month>\d{2})
		\k<date_separator>
		(?<day>\d{2})
		(?:
			(?:T|[ \t]+)
			(?<hour>\d{2})
			(?<time_separator>[:.-])
			(?<minute>\d{2})
			(?:
				\k<time_separator>
				(?<second>\d{2})
				(?<fraction>\.\d+)?
			)?
			(?:
				[ \t]*
				(?:
					(?<utc_timezone>Z)
					|
					(?<timezone_sign>[+-])
					(?<timezone_hour>\d{2})
					\k<time_separator>
					(?<timezone_minute>\d{2})
				)
			)?
		)?
		\z
	}x.freeze

	# Interprets one value as a strict boolean or a loose `true`/`false`
	# string. Returns `nil` when no boolean meaning can be inferred.
	def self.boolean(value)
		return value if value == true || value == false
		return nil unless value.is_a?(String)

		case value.strip.downcase
		when 'true'
			true
		when 'false'
			false
		else
			nil
		end
	end

	# Interprets one value as an integer or float when possible.
	def self.number(value)
		return value if value.is_a?(Integer) || value.is_a?(Float)
		return nil unless value.is_a?(String)

		stripped = value.strip
		return nil if stripped.empty?
		return stripped.to_i if stripped.match?(/\A[+-]?\d+\z/)
		return stripped.to_f if stripped.match?(/\A[+-]?\d+\.\d+\z/)

		nil
	end

	# Reports whether one value is numeric with no fractional component.
	def self.integral_number?(value)
		numeric_value = number(value)
		return false if numeric_value.nil?
		return true if numeric_value.is_a?(Integer)

		(numeric_value % 1).zero?
	end

	# Interprets one value as a datetime for explicitly date-aware operations.
	# Strings must satisfy `DATETIME_STRING_PATTERN`; captured components are
	# rebuilt as canonical ISO before the standard parser validates them.
	def self.datetime(value)
		return value if value.is_a?(DateTime)
		return value.to_datetime if value.is_a?(Time)
		return value.to_datetime if value.is_a?(Date)
		return nil unless value.is_a?(String)

		stripped = value.strip
		return nil if stripped.empty?

		match = DATETIME_STRING_PATTERN.match(stripped)
		return nil if match.nil?
		return nil unless valid_datetime_components?(match)

		DateTime.iso8601(canonical_datetime(match))
	rescue ArgumentError
		nil
	end

	# Alias retained because public filter config uses `date` language.
	def self.date(value)
		datetime(value)
	end

	# Converts one value into the generic comparable scalar form used by
	# exact filtering. Strings become numbers when possible, but date-shaped
	# strings remain strings unless a date-aware caller invokes `datetime`.
	def self.comparable(value, must_cast: false)
		return value if value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(DateTime)
		return value.to_datetime if value.is_a?(Time)
		return value.to_datetime if value.is_a?(Date)

		unless value.is_a?(String)
			return nil if must_cast

			return value
		end

		stripped = value.strip

		numeric_value = number(stripped)
		return numeric_value unless numeric_value.nil?

		return nil if must_cast

		stripped
	end

	# Rebuilds one lexical match as strict ISO text for calendar validation.
	def self.canonical_datetime(match)
		date = "#{match[:year]}-#{match[:month]}-#{match[:day]}"
		return date if match[:hour].nil?

		second = match[:second] || '00'
		fraction = match[:fraction].to_s
		timezone = canonical_timezone(match)

		"#{date}T#{match[:hour]}:#{match[:minute]}:#{second}#{fraction}#{timezone}"
	end
	private_class_method :canonical_datetime

	# Converts an optional loose timezone into canonical ISO syntax. Missing
	# timezone information deliberately means offset zero rather than local time.
	def self.canonical_timezone(match)
		return 'Z' unless match[:utc_timezone].nil?
		return 'Z' if match[:timezone_sign].nil?

		"#{match[:timezone_sign]}#{match[:timezone_hour]}:#{match[:timezone_minute]}"
	end
	private_class_method :canonical_timezone

	# Validates component ranges explicitly because `DateTime.iso8601` accepts
	# and normalises some out-of-range timezone offsets on older Ruby versions.
	def self.valid_datetime_components?(match)
		return false unless Date.valid_date?(match[:year].to_i, match[:month].to_i, match[:day].to_i)
		return true if match[:hour].nil?
		return false unless (0..23).cover?(match[:hour].to_i)
		return false unless (0..59).cover?(match[:minute].to_i)
		return false unless match[:second].nil? || (0..59).cover?(match[:second].to_i)
		return true if match[:timezone_sign].nil?

		(0..23).cover?(match[:timezone_hour].to_i) && (0..59).cover?(match[:timezone_minute].to_i)
	end
	private_class_method :valid_datetime_components?

	# Safe comparability check for mixed scalar types.
	def self.comparable_values?(left, right)
		return true if left.class == right.class
		return true if (left.is_a?(Integer) || left.is_a?(Float)) && (right.is_a?(Integer) || right.is_a?(Float))

		!((left <=> right).nil?)
	rescue ArgumentError, NoMethodError
		false
	end
end

end

end
end
end
