# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Alphabetic grouped-index builders plus shared range/token helpers.
# Structure: alphabetic groups are emitted first, while shared helpers
# provide range matching and token formatting for all grouping modes.
class GroupedIndex

	private

	def build_alphabetic_entries(candidates, config)
		start_token = config['start']
		token_length = start_token.length
		start_index = alphabetic_token_to_index(start_token)
		step_size = config['step']
		empty_groups = config['empty']
		other_label = config['other']

		grouped_items = {}
		other_items = []

		candidates.each do |candidate|
			alpha_token = candidate['alpha'].to_s
			unless candidate['alpha_starts_with_letter']
				other_items << candidate['item'] unless other_label.nil? || other_label.empty?
				next
			end

			next if alpha_token.length < token_length

			candidate_token = alpha_token[0, token_length]
			candidate_index = alphabetic_token_to_index(candidate_token)
			next if candidate_index < start_index

			group_index = ((candidate_index - start_index) / step_size).floor + 1
			grouped_items[group_index] ||= []
			grouped_items[group_index] << candidate['item']
		end

		if grouped_items.empty? && (other_items.empty? || !empty_groups)
			return [] unless empty_groups
		end

		max_group_index = grouped_items.keys.max || 0
		if max_group_index > MAXIMUM_AUTOMATIC_GROUPS
			raise ArgumentError, "Grouped indexing implies more than #{MAXIMUM_AUTOMATIC_GROUPS} groups; alphabetic grouped indexing requires narrower ranges."
		end

		if max_group_index.zero? && empty_groups
			max_group_index = 1
		end

		entries = []

		(1..max_group_index).each do |group_index|
			group_items = grouped_items.fetch(group_index, [])
			next if group_items.empty? && !empty_groups

			range_start_index = start_index + ((group_index - 1) * step_size)
			range_end_index = range_start_index + step_size - 1
			range_start_token = alphabetic_index_to_token(range_start_index, token_length)
			range_end_token = alphabetic_index_to_token(range_end_index, token_length)

			include_tokens = (range_start_index..range_end_index).map do |token_index|
				alphabetic_index_to_token(token_index, token_length)
			end

			entries << {
				'filters' => {
					@key => include_tokens.map { |token| "/^#{Regexp.escape(token)}/i" }
				},
				'values' => {
					@key => range_start_token
				},
				'token_values' => {
					@key => {
						'title' => range_start_token,
						'permalink' => range_start_token
					}
				},
				'group' => {
					'mode' => 'alphabetic',
					'start' => range_start_token,
					'end' => range_end_token,
					'order' => group_index,
					'range' => true,
					'other' => false
				},
				'items' => group_items.uniq
			}
		end

		if !other_label.nil? && !other_label.empty? && (!other_items.empty? || empty_groups)
			entries << {
				'filters' => {
					@key => '/^[^a-z]/i'
				},
				'values' => {
					@key => other_label
				},
				'token_values' => {
					@key => {
						'title' => other_label,
						'permalink' => other_label
					}
				},
				'group' => {
					'mode' => 'alphabetic',
					'start' => other_label,
					'end' => nil,
					'order' => (entries.length + 1),
					'range' => true,
					'other' => true
				},
				'items' => other_items.uniq
			}
		end

		entries
	end

	# Normalises alphabetic start token and enforces max token length.
	def normalise_alphabetic_start(raw_start)
		token = normalise_alpha_value(raw_start)['letters']
		if token.empty?
			raise ArgumentError, '`group.start` for alphabetic grouping must begin with letters.'
		end

		token[0, MAXIMUM_ALPHABETIC_TOKEN_LENGTH]
	end

	# Converts an alphabetic token to a zero-based numeric index.
	def alphabetic_token_to_index(token)
		token.each_char.reduce(0) do |memo, character|
			(memo * 26) + (character.ord - 'a'.ord)
		end
	end

	# Converts a zero-based numeric index to an alphabetic token with a
	# fixed number of characters.
	def alphabetic_index_to_token(index, length)
		maximum_index = (26**length) - 1
		clamped_index = [[index.to_i, 0].max, maximum_index].min
		token_characters = Array.new(length, 'a')
		cursor = clamped_index

		(length - 1).downto(0) do |position|
			token_characters[position] = (('a'.ord + (cursor % 26)).chr)
			cursor /= 26
		end

		token_characters.join
	end

	# Checks value inclusion for one span, using first-group inclusive
	# lower bounds and subsequent-group exclusive lower bounds.
	def range_value_within_span?(value, min_value, max_value, first_group:)
		if first_group
			return false if value < min_value
		else
			return false if value <= min_value
		end

		return true if max_value.nil?
		return false if value > max_value

		true
	end

	# Builds one range filter hash with the required min/max mode.
	def build_range_filter(min_value:, max_value:, min_inclusive:)
		filter = {}
		filter['min'] = min_value unless min_value.nil?
		filter['max'] = max_value unless max_value.nil?

		if max_value.nil?
			filter['mode'] = min_inclusive ? 'min-inclusive' : 'min-exclusive'
		elsif min_inclusive
			filter['mode'] = 'min-inclusive max-inclusive'
		else
			filter['mode'] = 'min-exclusive max-inclusive'
		end

		filter
	end

	# Formats numeric placeholder values compactly without losing
	# significant decimal precision.
	def format_numeric_token(value)
		numeric = value.to_f
		return numeric.to_i.to_s if (numeric % 1.0).zero?

		formatted = format('%.10f', numeric)
		formatted = formatted.chop while formatted.end_with?('0')
		formatted.sub(/\.\z/, '')
	end

	# Formats datetime token values for title placeholders.
	def format_datetime_title_token(value)
		value.strftime('%Y-%m-%d %H:%M:%S %z')
	end

	# Formats datetime token values for permalink placeholders.
	def format_datetime_permalink_token(value, include_time:)
		if include_time
			value.strftime('%Y-%m-%d-%H-%M-%S')
		else
			value.strftime('%Y-%m-%d')
		end
	end

	# Derives a default datetime start from observed values.
	#
	# Default behaviour:
	# - earliest candidate datetime
	# - aligned to a natural unit boundary based on step unit
	def infer_default_datetime_start(candidates, first_step)
		earliest_value = candidates.map { |candidate| candidate['datetime'] }.compact.min
		earliest_value = DateTime.now unless earliest_value.is_a?(DateTime)

		case first_step['unit']
		when 'year'
			DateTime.new(earliest_value.year, 1, 1, 0, 0, 0, earliest_value.offset)
		when 'month'
			DateTime.new(earliest_value.year, earliest_value.month, 1, 0, 0, 0, earliest_value.offset)
		when 'day'
			DateTime.new(earliest_value.year, earliest_value.month, earliest_value.day, 0, 0, 0, earliest_value.offset)
		when 'hour'
			DateTime.new(earliest_value.year, earliest_value.month, earliest_value.day, earliest_value.hour, 0, 0, earliest_value.offset)
		when 'minute'
			DateTime.new(earliest_value.year, earliest_value.month, earliest_value.day, earliest_value.hour, earliest_value.min, 0, earliest_value.offset)
		when 'second'
			DateTime.new(earliest_value.year, earliest_value.month, earliest_value.day, earliest_value.hour, earliest_value.min, earliest_value.sec, earliest_value.offset)
		else
			earliest_value
		end
	end

	# Interprets `now`/`today` keyword expressions with optional offsets.
	def interpret_datetime_keyword_expression(value, range_key:)
		expression = value.to_s.strip
		return nil if expression.empty?

		now_pattern = Regexp.escape(@now_keyword)
		now_match = expression.match(/\A#{now_pattern}(?:\s*([+-])\s*(\d+))?\z/i)
		unless now_match.nil?
			offset_seconds = now_match[2].nil? ? 0 : now_match[2].to_i
			offset_seconds = -offset_seconds if now_match[1] == '-'
			return DateTime.now + Rational(offset_seconds, 86_400)
		end

		today_pattern = Regexp.escape(@today_keyword)
		today_match = expression.match(/\A#{today_pattern}(?:\s*([+-])\s*(\d+))?\z/i)
		return nil if today_match.nil?

		offset_days = today_match[2].nil? ? 0 : today_match[2].to_i
		offset_days = -offset_days if today_match[1] == '-'

		current_time = DateTime.now
		target_date = current_time.to_date + offset_days

		if range_key == 'max'
			DateTime.new(target_date.year, target_date.month, target_date.day, 23, 59, 59, current_time.offset)
		else
			DateTime.new(target_date.year, target_date.month, target_date.day, 0, 0, 0, current_time.offset)
		end
	end

	# Interprets anchor expressions such as `year(today)` and `month(now)`.
	def interpret_datetime_anchor_expression(value)
		stripped = value.to_s.strip
		match = stripped.match(/\A(#{duration_keywords_pattern})\s*\((.+)\)\z/i)
		return nil if match.nil?

		unit = canonical_duration_unit(match[1])
		inner = match[2].to_s.strip
		anchor_time = interpret_datetime_keyword_expression(inner, range_key: 'min')
		return nil if anchor_time.nil?

		case unit
		when 'year'
			DateTime.new(anchor_time.year, 1, 1, 0, 0, 0, anchor_time.offset)
		when 'month'
			DateTime.new(anchor_time.year, anchor_time.month, 1, 0, 0, 0, anchor_time.offset)
		when 'day'
			DateTime.new(anchor_time.year, anchor_time.month, anchor_time.day, 0, 0, 0, anchor_time.offset)
		when 'hour'
			DateTime.new(anchor_time.year, anchor_time.month, anchor_time.day, anchor_time.hour, 0, 0, anchor_time.offset)
		when 'minute'
			DateTime.new(anchor_time.year, anchor_time.month, anchor_time.day, anchor_time.hour, anchor_time.min, 0, anchor_time.offset)
		when 'second'
			DateTime.new(anchor_time.year, anchor_time.month, anchor_time.day, anchor_time.hour, anchor_time.min, anchor_time.sec, anchor_time.offset)
		else
			nil
		end
	end
end

end
end
end
end
