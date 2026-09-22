# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Query

# Filter-normalisation helpers that convert public filter shorthand into
# one canonical internal tree model. Structure: each supported shorthand
# form is parsed and wrapped into consistent scalar/range/group nodes.
class Filter

	private

	def normalise_filter(filter)
		normalised = normalise_filter_definition(filter)
		return false if normalised == false
		return normalised if group_definition?(normalised)

		# Non-group shorthand is wrapped so downstream evaluation only needs
		# to process one canonical group shape.
		wrap_as_or_group([normalised])
	end

	# Normalises one filter definition node.
	def normalise_filter_definition(definition)
		case definition
		when Hash
			normalise_filter_hash(definition)
		when Array
			normalise_shortcut_array(definition)
		when String
			normalise_shortcut_string(definition)
		when Regexp, Integer, Float, Date, DateTime, Time
			normalise_scalar_shortcut(definition)
		else
			false
		end
	end

	# Routes hash definitions to grouped or local predicate handlers.
	def normalise_filter_hash(definition)
		hash_definition = Utils.stringify_keys(definition)
		return false if hash_definition.empty?

		if group_hash?(hash_definition)
			return false unless (hash_definition.keys - %w[include exclude join]).empty?

			return normalise_group_hash(hash_definition)
		end

		normalise_local_filter_hash(hash_definition)
	end

	# Detects group definitions by longhand keys.
	def group_hash?(hash_definition)
		hash_definition.key?('include') || hash_definition.key?('exclude')
	end

	# Normalises one local per-key filter hash into one implicit `and`
	# group when more than one predicate is present.
	def normalise_local_filter_hash(hash_definition)
		return false unless (hash_definition.keys - %w[exists match min max mode split]).empty?

		has_exists = hash_definition.key?('exists')
		has_match = hash_definition.key?('match')
		has_range = hash_definition.key?('min') || hash_definition.key?('max')
		return false unless has_exists || has_match || has_range

		filter_split = normalise_scalar_split(hash_definition['split'])
		return false if filter_split == :invalid

		mode_flags = normalise_mode_flags(
			hash_definition['mode'],
			has_match: has_match,
			has_min: hash_definition.key?('min'),
			has_max: hash_definition.key?('max')
		)
		return false if mode_flags == :invalid

		entries = []
		exists_type = nil

		if has_exists
			exists_definition = normalise_exists_definition(hash_definition['exists'], split: filter_split)
			return false if exists_definition == false

			exists_type = exists_definition['type']
			entries << exists_definition
		end

		if has_match
			scalar_definition = normalise_local_scalar_definition(hash_definition['match'], split: filter_split, mode_flags: mode_flags)
			return false if scalar_definition == false

			entries << scalar_definition
		end

		if has_range
			range_definition = normalise_local_range_definition(hash_definition, split: filter_split, mode_flags: mode_flags, exists_type: exists_type)
			return false if range_definition == false

			entries << range_definition
		end

		return false if entries.empty?
		return entries.first if entries.length == 1

		{
			'include' => entries,
			'exclude' => [],
			'join' => 'and'
		}
	end

	# Normalises longhand grouped definitions.
	def normalise_group_hash(hash_definition)
		include_entries = []
		if hash_definition.key?('include')
			parsed_include = normalise_group_entries(hash_definition['include'])
			return false if parsed_include == false

			include_entries.concat(parsed_include)
		end

		exclude_entries = []
		if hash_definition.key?('exclude')
			parsed_exclude = normalise_group_entries(hash_definition['exclude'])
			return false if parsed_exclude == false

			exclude_entries.concat(parsed_exclude)
		end

		return false if include_entries.empty? && exclude_entries.empty?

		{
			'include' => include_entries,
			'exclude' => exclude_entries,
			'join' => normalise_join(hash_definition['join'])
		}
	end

	# Normalises include/exclude members. Each member is itself a filter
	# definition instance and is normalised recursively.
	def normalise_group_entries(raw_entries)
		entries = normalise_delimited_entries(raw_entries)
		return false unless entries.is_a?(Array)

		normalised_entries = entries.map { |entry| normalise_filter_definition(entry) }.reject { |entry| entry == false }
		return false if normalised_entries.empty?

		normalised_entries
	end

	# Normalises array shorthand as `include: <entries>, join: or`.
	def normalise_shortcut_array(raw_entries)
		entries = raw_entries.flatten.compact
		return false if entries.empty?

		normalised_entries = entries.map { |entry| normalise_filter_definition(entry) }.reject { |entry| entry == false }
		return false if normalised_entries.empty?

		wrap_as_or_group(normalised_entries)
	end

	# Normalises scalar string shorthand.
	# Delimited strings become an `or` group of scalar shortcuts.
	def normalise_shortcut_string(raw_value)
		split_values = Utils.split_delimited_string(raw_value.to_s, @split_delimiter)
		return false if split_values.empty?

		if split_values.length == 1
			return normalise_scalar_shortcut(split_values.first)
		end

		normalised_entries = split_values.map { |value| normalise_scalar_shortcut(value) }.reject { |entry| entry == false }
		return false if normalised_entries.empty?

		wrap_as_or_group(normalised_entries)
	end

	# Scalar shortcut:
	# `{ match: <scalar>, mode: auto, split: true }`.
	# Split `true` resolves to the configured global split delimiter.
	def normalise_scalar_shortcut(raw_value)
		scalar_match = normalise_scalar_match_value(raw_value)
		return false if scalar_match == false

		{
			'match' => scalar_match,
			'mode' => 'auto',
			'split' => @split_delimiter
		}
	end

	# Normalises one explicit exists predicate.
	def normalise_exists_definition(raw_exists, split:)
		if raw_exists == true || raw_exists == false
			return {
				'exists' => raw_exists,
				'type' => nil,
				'split' => split
			}
		end

		type = raw_exists.to_s.strip.downcase
		type = 'date' if type == 'datetime'
		type = type == 'true' ? true : type
		type = false if type == 'false'

		if type == true || type == false
			return {
				'exists' => type,
				'type' => nil,
				'split' => split
			}
		end

		return false unless %w[array string boolean int float date].include?(type)

		{
			'exists' => true,
			'type' => type,
			'split' => split
		}
	end

	# Normalises one scalar predicate from a local filter hash.
	def normalise_local_scalar_definition(raw_match, split:, mode_flags:)
		scalar_match = normalise_scalar_match_value(raw_match)
		return false if scalar_match == false

		normalised = {
			'match' => scalar_match,
			'mode' => mode_flags['scalar_mode'],
			'split' => split
		}

		if mode_flags['scalar_mode'] == 'first'
			normalised['first'] = mode_flags['first']
		end

		normalised
	end

	# Normalises scalar match values, including regex literal strings.
	def normalise_scalar_match_value(value)
		if value.is_a?(String)
			parse_scalar(value.strip)
		elsif value.is_a?(Regexp) || value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)
			normalise_comparable_scalar(value)
		else
			false
		end
	end

	# Normalises one shared mode token string into scalar/range fragments.
	def normalise_mode_flags(raw_mode, has_match:, has_min:, has_max:)
		scalar_mode = nil
		embedded_first_count = nil
		min_inclusive = nil
		max_inclusive = nil

		mode_tokens = raw_mode.to_s.strip.downcase.split(/\s+/).reject(&:empty?)
		mode_tokens.each do |token|
			case token
			when 'auto', 'strict', 'only'
				return :invalid unless has_match
				return :invalid unless scalar_mode.nil?

				scalar_mode = token
			when 'first'
				return :invalid unless has_match
				return :invalid unless scalar_mode.nil?

				scalar_mode = 'first'
			when /\Afirst\(\s*(\d+)\s*\)\z/
				return :invalid unless has_match
				return :invalid unless scalar_mode.nil?

				scalar_mode = 'first'
				embedded_first_count = Regexp.last_match(1).to_i
			when 'inclusive'
				return :invalid unless has_min || has_max
				return :invalid if (has_min && !min_inclusive.nil?) || (has_max && !max_inclusive.nil?)

				min_inclusive = true if has_min
				max_inclusive = true if has_max
			when 'exclusive'
				return :invalid unless has_min || has_max
				return :invalid if (has_min && !min_inclusive.nil?) || (has_max && !max_inclusive.nil?)

				min_inclusive = false if has_min
				max_inclusive = false if has_max
			when 'min-inclusive'
				return :invalid unless has_min
				return :invalid unless min_inclusive.nil?

				min_inclusive = true
			when 'min-exclusive'
				return :invalid unless has_min
				return :invalid unless min_inclusive.nil?

				min_inclusive = false
			when 'max-inclusive'
				return :invalid unless has_max
				return :invalid unless max_inclusive.nil?

				max_inclusive = true
			when 'max-exclusive'
				return :invalid unless has_max
				return :invalid unless max_inclusive.nil?

				max_inclusive = false
			else
				return :invalid
			end
		end

		scalar_mode = 'auto' if has_match && scalar_mode.nil?
		first_count = nil
		if scalar_mode == 'first'
			first_count = normalise_scalar_first_count(nil, embedded_first_count)
			return :invalid if first_count == :invalid
		end

		if has_min
			min_inclusive = true if min_inclusive.nil?
		elsif !min_inclusive.nil?
			return :invalid
		end

		if has_max
			max_inclusive = true if max_inclusive.nil?
		elsif !max_inclusive.nil?
			return :invalid
		end

		range_mode = nil
		if has_min || has_max
			range_fragments = []
			range_fragments << (min_inclusive ? 'min-inclusive' : 'min-exclusive') if has_min
			range_fragments << (max_inclusive ? 'max-inclusive' : 'max-exclusive') if has_max
			range_mode = range_fragments.join(' ')
		end

		{
			'scalar_mode' => scalar_mode,
			'first' => first_count,
			'range_mode' => range_mode
		}
	end

	# Normalises the `first` count used by `mode: first`.
	# Defaults to 1 when not supplied.
	def normalise_scalar_first_count(raw_first, embedded_default = nil)
		return embedded_default if !embedded_default.nil? && embedded_default.positive?

		return 1 if raw_first.nil?

		if raw_first.is_a?(Integer)
			return raw_first if raw_first.positive?

			return :invalid
		end

		if raw_first.is_a?(Float)
			return raw_first.to_i if raw_first.positive? && (raw_first % 1).zero?

			return :invalid
		end

		return :invalid unless raw_first.is_a?(String)

		stripped = raw_first.strip
		return :invalid if stripped.empty?

		return stripped.to_i if stripped.match?(/\A\d+\z/) && stripped.to_i.positive?

		:invalid
	end

	# Normalises scalar split configuration.
	# - nil / true => global split delimiter
	# - false => disable splitting
	# - non-empty string => explicit delimiter override
	def normalise_scalar_split(raw_split)
		return @split_delimiter if raw_split.nil?
		return @split_delimiter if raw_split == true
		return false if raw_split == false

		return :invalid unless raw_split.is_a?(String)

		lowered = raw_split.strip.downcase
		return @split_delimiter if lowered == 'true'
		return false if lowered == 'false'

		return :invalid if raw_split.empty?

		raw_split
	end

	# Normalises one range predicate from a local filter hash.
	def normalise_local_range_definition(hash_definition, split:, mode_flags:, exists_type:)
		target = %w[array string].include?(exists_type) ? 'length' : 'value'
		normalise_range_hash(hash_definition, split: split, mode_flags: mode_flags, target: target)
	end

	# Builds one canonical range node from the configured min/max options.
	def normalise_range_hash(hash_definition, split:, mode_flags:, target:)
		range_hash = {
			'split' => split,
			'target' => target
		}

		%w[min max].each do |range_key|
			next unless hash_definition.key?(range_key)

			parsed_value = if target == 'length'
										 interpret_length_boundary(hash_definition[range_key])
									 else
										 interpret_numeric_or_date_keyword(hash_definition[range_key], range_key: range_key)
									 end
			return false if parsed_value == false

			range_hash[range_key] = parsed_value
		end

		return false if range_hash['min'].nil? && range_hash['max'].nil?

		if !range_hash['min'].nil? && !range_hash['max'].nil?
			min_value = range_hash['min']
			max_value = range_hash['max']

			# Coerce comparable types before we validate ordering.
			if target == 'length'
				return false unless numeric?(min_value) && numeric?(max_value)

				min_value = min_value.to_f
				max_value = max_value.to_f
			elsif numeric?(min_value) && numeric?(max_value)
				min_value = min_value.to_f
				max_value = max_value.to_f
			elsif date_like?(min_value) && date_like?(max_value)
				min_value = normalise_comparable_scalar(min_value)
				max_value = normalise_comparable_scalar(max_value)
			elsif min_value.class != max_value.class
				return false
			end

			if min_value > max_value
				log_warning("Range filter has min greater than max (#{min_value} > #{max_value}); swapping the bounds.")
				min_value, max_value = max_value, min_value
			end

			range_hash['min'] = min_value
			range_hash['max'] = max_value
		end

		range_hash['mode'] = mode_flags['range_mode']

		range_hash
	end

	# Parses one numeric-only boundary used for array/string length checks.
	def interpret_length_boundary(value)
		numeric_value = Jekyll::Plugins::PaginateV3::Support::LooseScalar.number(value)
		numeric_value.nil? ? false : numeric_value
	end

	# Converts grouped entry inputs into an array without blank items.
	# Strings are split by the configured global delimiter.
	def normalise_delimited_entries(raw_entries)
		if raw_entries.is_a?(Array)
			raw_entries.flatten.compact
		elsif raw_entries.is_a?(String)
			Utils.delimited_array(raw_entries, delimiter: @split_delimiter)
		elsif raw_entries.nil?
			[]
		else
			[raw_entries]
		end
	end

	# Wraps a list of entries as a default `or` group.
	def wrap_as_or_group(entries)
		{
			'include' => entries,
			'exclude' => [],
			'join' => 'or'
		}
	end

	# Normalises group join mode.
	def normalise_join(raw_join)
		join_value = raw_join.to_s.strip.downcase
		%w[or and].include?(join_value) ? join_value : 'or'
	end

	# Parses scalar filter values, including regex literals.
	def parse_scalar(value)
		if value =~ %r{\A/(.*?)/([imx]*)\z}
			source = Regexp.last_match(1)
			flags = Regexp.last_match(2)
			options = 0
			options |= Regexp::IGNORECASE if flags.include?('i')
			options |= Regexp::MULTILINE if flags.include?('m')
			options |= Regexp::EXTENDED if flags.include?('x')
			begin
				return Regexp.new(source, options)
			rescue RegexpError
				return false
			end
		end

		interpret_numeric(value)
	end

	# Parses numeric/date range endpoints and supports configurable
	# `keywords.now` and `keywords.today`.
	#
	# Examples (assuming default keywords):
	# - now
	# - now+90
	# - today
	# - today-1
	def interpret_numeric_or_date_keyword(value, range_key: nil)
		if value.is_a?(String)
			# Keywords are checked first so string forms like `today+1` are not
			# misread as ordinary scalar strings.
			now_expression = interpret_now_expression(value)
			return now_expression unless now_expression.nil?

			today_expression = interpret_today_expression(value, range_key: range_key)
			return today_expression unless today_expression.nil?
		end

		numeric_value = Jekyll::Plugins::PaginateV3::Support::LooseScalar.number(value)
		return numeric_value unless numeric_value.nil?

		datetime_value = Jekyll::Plugins::PaginateV3::Support::LooseScalar.datetime(value)
		return datetime_value unless datetime_value.nil?

		false
	end

	# Parses configured now-keyword expressions into DateTime values.
	# Offsets are in whole seconds.
	def interpret_now_expression(value)
		keyword_pattern = Regexp.escape(@now_keyword)
		expression = value.to_s.strip
		match = expression.match(/\A#{keyword_pattern}(?:\s*([+-])\s*(\d+))?\z/i)
		return nil if match.nil?

		offset_seconds = match[2].nil? ? 0 : match[2].to_i
		offset_seconds = -offset_seconds if match[1] == '-'

		DateTime.now + Rational(offset_seconds, 86_400)
	end

	# Parses configured today-keyword expressions into DateTime values.
	#
	# Offsets are in whole days and the parsed value is normalised to the
	# start or end of the day depending on whether the value is used as a
	# `min` or `max` range endpoint.
	def interpret_today_expression(value, range_key:)
		keyword_pattern = Regexp.escape(@today_keyword)
		expression = value.to_s.strip
		match = expression.match(/\A#{keyword_pattern}(?:\s*([+-])\s*(\d+))?\z/i)
		return nil if match.nil?

		offset_days = match[2].nil? ? 0 : match[2].to_i
		offset_days = -offset_days if match[1] == '-'

		current_time = DateTime.now
		target_date = current_time.to_date + offset_days

		if range_key == 'max'
			DateTime.new(target_date.year, target_date.month, target_date.day, 23, 59, 59, current_time.offset)
		else
			DateTime.new(target_date.year, target_date.month, target_date.day, 0, 0, 0, current_time.offset)
		end
	end

	# Casts string values to Integer or Float when possible.
	# Returns the original string unless strict casting is requested.
	def interpret_numeric(value, must_cast: false)
		comparable_value = Jekyll::Plugins::PaginateV3::Support::LooseScalar.comparable(value, must_cast: must_cast)
		return false if comparable_value.nil? && must_cast

		comparable_value
	end

	# Normalises values to a comparable scalar form.
	def normalise_comparable_scalar(value)
		Jekyll::Plugins::PaginateV3::Support::LooseScalar.comparable(value)
	end

	# Numeric type check used by range coercion.
	def numeric?(value)
		value.is_a?(Integer) || value.is_a?(Float)
	end

	# Date-like type check used by range coercion.
	def date_like?(value)
		value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)
	end
end

end
end
end
end
