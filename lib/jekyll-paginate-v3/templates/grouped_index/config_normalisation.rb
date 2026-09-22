# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Grouped-index config normalisation for numeric, datetime, and alphabetic
# modes. Structure: raw group config is validated and converted into
# canonical step/start/growth settings consumed by entry builders.
class GroupedIndex

	private
	
	def normalise_numeric_group_config
		if @raw_group.is_a?(Integer) || @raw_group.is_a?(Float) || (@raw_group.is_a?(String) && numeric_string?(@raw_group))
			step_value = parse_positive_numeric(@raw_group, name: 'group')
			return {
				'start' => 0.0,
				'step_pattern' => [step_value],
				'grow' => 1.0,
				'min_step' => nil,
				'max_step' => nil,
				'empty' => false,
				'total' => nil
			}
		end

		hash_group = Utils.safe_hash(@raw_group)
		if hash_group.empty?
			raise ArgumentError, '`group` must be numeric, string, or hash for grouped numeric indexing.'
		end

		allowed_keys = %w[start step grow min max empty total]
		validate_allowed_keys!(hash_group, allowed_keys, context: 'numeric')

		unless hash_group.key?('step')
			raise ArgumentError, '`group.step` is required for numeric grouped indexing.'
		end

		step_pattern = parse_numeric_step_pattern(hash_group['step'])
		if step_pattern.length > 1 && hash_group.key?('grow')
			raise ArgumentError, '`group.step` arrays cannot be used together with `group.grow`.'
		end

		grow_factor = if hash_group.key?('grow')
										parse_grow_factor(hash_group['grow'])
									else
										1.0
									end

		{
			'start' => hash_group.key?('start') ? parse_numeric(hash_group['start'], name: 'group.start') : 0.0,
			'step_pattern' => step_pattern,
			'grow' => grow_factor,
			'min_step' => hash_group.key?('min') ? parse_positive_numeric(hash_group['min'], name: 'group.min') : nil,
			'max_step' => hash_group.key?('max') ? parse_positive_numeric(hash_group['max'], name: 'group.max') : nil,
			'empty' => parse_boolean(hash_group['empty']),
			'total' => hash_group.key?('total') ? parse_total_group_count(hash_group['total']) : nil
		}
	end

	# Parses and validates datetime grouping configuration.
	def normalise_datetime_group_config(candidates)
		raw_group_hash = if @raw_group.is_a?(Hash)
												Utils.safe_hash(@raw_group)
											else
												{
													'step' => @raw_group
												}
											end

		allowed_keys = %w[start step grow min max empty total]
		validate_allowed_keys!(raw_group_hash, allowed_keys, context: 'datetime')

		unless raw_group_hash.key?('step')
			raise ArgumentError, '`group.step` is required for datetime grouped indexing.'
		end

		step_pattern = parse_datetime_step_pattern(raw_group_hash['step'])
		if step_pattern.length > 1 && raw_group_hash.key?('grow')
			raise ArgumentError, '`group.step` arrays cannot be used together with `group.grow`.'
		end

		grow_factor = if raw_group_hash.key?('grow')
										parse_grow_factor(raw_group_hash['grow'])
									else
										1.0
									end

		inferred_start = infer_default_datetime_start(candidates, step_pattern.first)
		configured_start = raw_group_hash.key?('start') ? parse_datetime_start(raw_group_hash['start']) : inferred_start

		{
			'start' => configured_start,
			'step_pattern' => step_pattern,
			'grow' => grow_factor,
			'min_step' => raw_group_hash.key?('min') ? parse_datetime_duration(raw_group_hash['min'], name: 'group.min') : nil,
			'max_step' => raw_group_hash.key?('max') ? parse_datetime_duration(raw_group_hash['max'], name: 'group.max') : nil,
			'empty' => parse_boolean(raw_group_hash['empty']),
			'total' => raw_group_hash.key?('total') ? parse_total_group_count(raw_group_hash['total']) : nil,
			'time_precision' => datetime_time_precision?(raw_group_hash, step_pattern)
		}
	end

	# Parses and validates alphabetic grouping configuration.
	def normalise_alphabetic_group_config
		if @raw_group.is_a?(String)
			return {
				'start' => normalise_alphabetic_start(@raw_group),
				'step' => 1,
				'empty' => false,
				'other' => nil
			}
		end

		hash_group = Utils.safe_hash(@raw_group)
		if hash_group.empty?
			raise ArgumentError, '`group` must be a string or hash for alphabetic grouped indexing.'
		end

		allowed_keys = %w[start step empty other]
		validate_allowed_keys!(hash_group, allowed_keys, context: 'alphabetic')

		unless hash_group.key?('step')
			raise ArgumentError, '`group.step` is required for alphabetic grouped indexing.'
		end

		step_value = parse_positive_integer(hash_group['step'], name: 'group.step')
		if step_value > MAXIMUM_STEP.to_i
			raise ArgumentError, '`group.step` is too large for alphabetic grouped indexing.'
		end

		{
			'start' => normalise_alphabetic_start(hash_group.key?('start') ? hash_group['start'] : 'a'),
			'step' => step_value,
			'empty' => parse_boolean(hash_group['empty']),
			'other' => hash_group.key?('other') ? hash_group['other'].to_s : nil
		}
	end

	# Validates that no unsupported keys are present in grouped config.
	def validate_allowed_keys!(hash_group, allowed_keys, context:)
		invalid_keys = hash_group.keys - allowed_keys
		return if invalid_keys.empty?

		raise ArgumentError, "Invalid keys for #{context} grouped indexing: #{invalid_keys.join(', ')}."
	end

	# Parses numeric step definitions.
	def parse_numeric_step_pattern(raw_step)
		if raw_step.is_a?(Array)
			pattern = raw_step.flatten.compact.map { |entry| parse_positive_numeric(entry, name: 'group.step[]') }
			raise ArgumentError, '`group.step` array must include at least one positive value.' if pattern.empty?

			return pattern
		end

		[parse_positive_numeric(raw_step, name: 'group.step')]
	end

	# Parses datetime step definitions.
	def parse_datetime_step_pattern(raw_step)
		if raw_step.is_a?(Array)
			pattern = raw_step.flatten.compact.map { |entry| parse_datetime_duration(entry, name: 'group.step[]') }
			raise ArgumentError, '`group.step` array must include at least one positive duration.' if pattern.empty?

			return pattern
		end

		[parse_datetime_duration(raw_step, name: 'group.step')]
	end

	# Parses one grow factor and validates supported bounds.
	def parse_grow_factor(raw_grow)
		grow_value = parse_positive_numeric(raw_grow, name: 'group.grow')
		if grow_value < MINIMUM_GROW || grow_value > MAXIMUM_GROW
			raise ArgumentError, "`group.grow` must be between #{MINIMUM_GROW} and #{MAXIMUM_GROW}."
		end

		grow_value
	end

	# Parses one configured total group count.
	def parse_total_group_count(raw_total)
		total = parse_positive_integer(raw_total, name: 'group.total')
		if total < 1 || total > MAXIMUM_TOTAL_GROUPS
			raise ArgumentError, "`group.total` must be within 1..#{MAXIMUM_TOTAL_GROUPS}."
		end

		total
	end

	# Parses any numeric scalar; raises for non-numeric values.
	def parse_numeric(raw_value, name:)
		numeric_value = interpret_numeric_value(raw_value)
		if numeric_value.nil?
			raise ArgumentError, "`#{name}` must be numeric."
		end

		numeric_value.to_f
	end

	# Parses strictly positive numeric values.
	def parse_positive_numeric(raw_value, name:)
		numeric_value = parse_numeric(raw_value, name: name)
		if numeric_value <= 0.0
			raise ArgumentError, "`#{name}` must be greater than zero."
		end

		numeric_value
	end

	# Parses strictly positive integers.
	def parse_positive_integer(raw_value, name:)
		integer_value = parse_numeric(raw_value, name: name).to_i
		if integer_value <= 0
			raise ArgumentError, "`#{name}` must be a positive integer."
		end

		integer_value
	end

	# Parses loose boolean values.
	def parse_boolean(raw_value)
		Jekyll::Plugins::PaginateV3::Support::LooseScalar.boolean(raw_value) == true
	end

	# Parses datetime start values including:
	# - absolute datetimes
	# - `now` / `today` expressions with optional integer offsets
	# - anchored expressions such as `year(today)`, `month(now)`
	def parse_datetime_start(raw_value)
		return raw_value.to_datetime if raw_value.is_a?(DateTime)
		return raw_value.to_datetime if raw_value.is_a?(Time)
		return raw_value.to_datetime if raw_value.is_a?(Date)

		if raw_value.is_a?(Integer) || raw_value.is_a?(Float)
			return DateTime.new(1970, 1, 1, 0, 0, 0) + Rational((raw_value.to_f * 86_400).round, 86_400)
		end

		unless raw_value.is_a?(String)
			raise ArgumentError, '`group.start` for datetime grouping must be date-like, keyword-like, or numeric.'
		end

		stripped = raw_value.strip
		raise ArgumentError, '`group.start` for datetime grouping cannot be blank.' if stripped.empty?

		anchored = interpret_datetime_anchor_expression(stripped)
		return anchored unless anchored.nil?

		keyword_value = interpret_datetime_keyword_expression(stripped, range_key: 'min')
		return keyword_value unless keyword_value.nil?

		datetime_value = Jekyll::Plugins::PaginateV3::Support::LooseScalar.datetime(stripped)
		return datetime_value unless datetime_value.nil?

		raise ArgumentError
	rescue ArgumentError
		raise ArgumentError, "`group.start` could not be parsed as datetime: #{raw_value.inspect}."
	end

	# Parses datetime duration definitions used by `step`, `min`, and
	# `max` in datetime grouped indexing.
	#
	# Supported forms:
	# - Numeric (days)
	# - `day(x)`, `month(x)`, `year(x)`, `hour(x)`, `minute(x)`, `second(x)`
	def parse_datetime_duration(raw_value, name:)
		if raw_value.is_a?(Integer) || raw_value.is_a?(Float)
			amount = raw_value.to_f
			raise ArgumentError, "`#{name}` must be greater than zero." if amount <= 0.0

			return {
				'unit' => 'day',
				'amount' => amount
			}
		end

		unless raw_value.is_a?(String)
			raise ArgumentError, "`#{name}` must be numeric or a duration token."
		end

		stripped = raw_value.strip
		raise ArgumentError, "`#{name}` cannot be blank." if stripped.empty?

		if numeric_string?(stripped)
			amount = stripped.to_f
			raise ArgumentError, "`#{name}` must be greater than zero." if amount <= 0.0

			return {
				'unit' => 'day',
				'amount' => amount
			}
		end

		bare_unit = canonical_duration_unit(stripped)
		unless bare_unit.nil?
			return {
				'unit' => bare_unit,
				'amount' => 1.0
			}
		end

		match = stripped.match(/\A(#{duration_keywords_pattern})\s*\((.+)\)\z/i)
		if match.nil?
			raise ArgumentError, "`#{name}` must be numeric or one of: #{@duration_keyword_by_unit.values.join(', ')}(x)."
		end

		unit = canonical_duration_unit(match[1])
		amount_text = match[2].to_s.strip
		amount = parse_numeric(amount_text, name: name)

		if amount <= 0.0
			raise ArgumentError, "`#{name}` must be greater than zero."
		end

		if CALENDAR_UNITS.include?(unit) && (amount % 1.0).positive?
			raise ArgumentError, "`#{name}` for unit #{unit} must be a whole number."
		end

		{
			'unit' => unit,
			'amount' => amount
		}
	end

	# Detects whether datetime permalink placeholders should include
	# clock-level precision.
	def datetime_time_precision?(raw_hash, step_pattern)
		return true if step_pattern.any? { |step| %w[hour minute second].include?(step['unit']) }
		return true if step_pattern.any? { |step| step['unit'] == 'day' && (step['amount'] % 1.0).positive? }
		return true if raw_hash.key?('start') && datetime_start_has_time_precision?(raw_hash['start'])

		%w[min max].any? do |key|
			next false unless raw_hash.key?(key)

			begin
				duration = parse_datetime_duration(raw_hash[key], name: "group.#{key}")
				%w[hour minute second].include?(duration['unit']) || (duration['unit'] == 'day' && (duration['amount'] % 1.0).positive?)
			rescue StandardError
				false
			end
		end
	end

	# Indicates whether a datetime `start` expression implies clock-level
	# precision in permalink placeholders.
	def datetime_start_has_time_precision?(raw_start)
		return true if raw_start.is_a?(Time)
		return true if raw_start.is_a?(DateTime) && (raw_start.hour.positive? || raw_start.min.positive? || raw_start.sec.positive?)

		return false unless raw_start.is_a?(String)

		stripped = raw_start.strip
		return false if stripped.empty?
		precise_units = [@duration_keyword_by_unit['hour'], @duration_keyword_by_unit['minute'], @duration_keyword_by_unit['second']].map { |keyword| Regexp.escape(keyword) }.join('|')
		return true if stripped.match?(/\A(?:#{precise_units})(?:\s*\(|\z)/i)
		return true if stripped.match?(/\A#{Regexp.escape(@now_keyword)}(?:\s*[+-]\s*\d+)?\z/i)

		parsed = Jekyll::Plugins::PaginateV3::Support::LooseScalar.datetime(stripped)
		return false if parsed.nil?

		parsed.hour.positive? || parsed.min.positive? || parsed.sec.positive?
	end
end

end
end
end
end
