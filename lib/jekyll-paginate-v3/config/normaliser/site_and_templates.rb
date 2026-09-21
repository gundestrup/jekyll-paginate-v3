# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Config

# Site and template config normalisation helpers used by `Normaliser`.
# Structure: site-level keys are canonicalised first, then template
# defaults and per-template settings are normalised for runtime use.
class Normaliser
	class << self

		private
		def normalise_site_pagination_source(raw_pagination)
			source = Utils.deep_copy(Utils.safe_hash(raw_pagination))

			syntax = Utils.safe_hash(source['syntax'])
			syntax['split'] = source['split'] if source.key?('split') && !syntax.key?('split')
			syntax['separator'] = source['separator'] if source.key?('separator') && !syntax.key?('separator')
			if source.key?('nested_key_separator') && !syntax.key?('separator') && !syntax.key?('nested_key_separator')
				syntax['separator'] = source['nested_key_separator']
			end
			source['syntax'] = syntax unless syntax.empty?

			templates = Utils.safe_hash(source['templates'])
			templates.delete('defaults')

			(template_setting_keys + legacy_template_alias_keys).each do |key|
				next unless templates.key?(key)
				next if source.key?(key)

				source[key] = templates[key]
			end

			template_setting_keys.each { |key| templates.delete(key) }
			legacy_template_alias_keys.each { |key| templates.delete(key) }
			source['templates'] = templates unless templates.empty?

			LEGACY_SITE_KEY_ALIASES.each { |legacy_key| source.delete(legacy_key) }

			source
		end

		# Purpose: Normalises site common into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `config`, `compatibility_mode`, `raw_overrides`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_site_common!(config, compatibility_mode, raw_overrides = nil)
			config['enabled'] = !!config['enabled']
			config['debug'] = !!config['debug']
			config['compatibility'] = compatibility_mode if compatibility_mode

			config['syntax'] = normalise_syntax(config['syntax'])
			split_delimiter = config.dig('syntax', 'split')

			config['keywords'] = normalise_keywords(config['keywords'])
			config['equivalents'] = normalise_equivalents(config['equivalents'], split_delimiter)
			config['templates'] = normalise_templates(
				config['templates'],
				keywords: config['keywords']
			)

			normalised_template_defaults = normalise_template_defaults(
				extract_site_template_defaults(config),
				raw_overrides: raw_overrides,
				split_delimiter: split_delimiter,
				keywords: config['keywords']
			)
			apply_template_defaults_to_site_config!(config, normalised_template_defaults)
		end

		# Resolves template syntax from local overrides, accepting both the
		# modern nested syntax hash and legacy root aliases.
		def resolve_template_syntax(raw_template_pagination, site_syntax)
			syntax = normalise_syntax(raw_template_pagination['syntax'], fallback: site_syntax)

			if raw_template_pagination.key?('split')
				syntax['split'] = normalise_split(raw_template_pagination['split'], syntax['split'])
			end

			if raw_template_pagination.key?('separator')
				separator = raw_template_pagination['separator'].to_s
				syntax['separator'] = separator.strip.empty? ? syntax['separator'] : separator
			elsif raw_template_pagination.key?('nested_key_separator')
				separator = raw_template_pagination['nested_key_separator'].to_s
				syntax['separator'] = separator.strip.empty? ? syntax['separator'] : separator
			end

			syntax
		end

		# Purpose: Normalises syntax into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_syntax`, `fallback`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_syntax(raw_syntax, fallback: nil)
			defaults = Utils.deep_copy(DEFAULTS['syntax'])
			defaults = defaults.merge(Utils.safe_hash(fallback)) if fallback.is_a?(Hash)
			syntax = defaults.merge(Utils.safe_hash(raw_syntax))

			separator = syntax['separator']
			if (separator.nil? || separator.to_s.strip.empty?) && syntax.key?('nested_key_separator')
				separator = syntax['nested_key_separator']
			end
			separator = defaults['separator'] if separator.to_s.strip.empty?

			{
				'separator' => separator.to_s,
				'split' => normalise_split(syntax['split'], defaults['split'])
			}
		end

		# Purpose: Normalises compatibility into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_value`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_compatibility(raw_value)
			value = raw_value.to_s.strip.downcase
			return nil if value.empty?
			return value if %w[v1 v2].include?(value)

			nil
		end

		# Purpose: Normalises split into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_split`, `default_split`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_split(raw_split, default_split = DEFAULTS.dig('syntax', 'split'))
			Utils.normalise_split_delimiter(raw_split, default_split)
		end

		# Purpose: Normalises keywords into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_keywords`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_keywords(raw_keywords)
			defaults = Utils.deep_copy(KEYWORD_DEFAULTS)
			keywords = defaults.merge(Utils.safe_hash(raw_keywords))

			keywords.each do |key, value|
				keywords[key] = value.to_s.strip
				keywords[key] = defaults[key] if keywords[key].empty?
			end

			invalid_keywords = keywords.select { |_, value| !value.match?(/\A[a-z]+\z/) }
			unless invalid_keywords.empty?
				raise ArgumentError, "pagination.keywords values must match [a-z]+. Invalid entries: #{invalid_keywords.map { |key, value| "#{key}=#{value}" }.join(', ')}."
			end

			duplicate_values = keywords.values.group_by { |value| value }.select { |_, values| values.length > 1 }.keys
			unless duplicate_values.empty?
				raise ArgumentError, "pagination.keywords values must be unique. Duplicates: #{duplicate_values.join(', ')}."
			end

			keywords
		end

		# Purpose: Normalises equivalents into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_equivalents`, `split_delimiter`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_equivalents(raw_equivalents, split_delimiter)
			return false if raw_equivalents == false

			groups = if raw_equivalents.is_a?(Array)
							raw_equivalents
						elsif raw_equivalents.nil?
							[]
						else
							[raw_equivalents]
						end
			return Utils.deep_copy(DEFAULTS['equivalents']) if groups.empty?

			groups.map do |group|
				entries = if group.is_a?(Array)
								group.flat_map { |entry| Utils.delimited_array(entry, delimiter: split_delimiter) }
							else
								Utils.delimited_array(group, delimiter: split_delimiter)
							end

				entries.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
			end.reject { |group| group.length < 2 }
		end

		# Purpose: Normalises templates into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_templates`, `keywords`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_templates(raw_templates, keywords:)
			defaults = Utils.deep_copy(DEFAULTS['templates'])
			source_hash = Utils.safe_hash(raw_templates)
			source = defaults.merge(source_hash)
			source.delete('defaults')

			# Default to the currently configured site-pages keyword so changing it
			# does not make the default location collide with a collection label.
			source['location'] = keywords['pages'] if source['location'].nil? || source['location'].to_s.strip.empty?
			source['generate'] = if source['generate'].is_a?(Array)
										source['generate'].map { |entry| normalise_generated_template_definition(entry) }
									elsif source['generate'].is_a?(Hash)
										[normalise_generated_template_definition(source['generate'])]
									else
										[]
									end

			template_setting_keys.each { |key| source.delete(key) }
			legacy_template_alias_keys.each { |key| source.delete(key) }

			source
		end

		# Validates settings that generated templates otherwise would not
		# normalise until their in-memory template objects are processed.
		def normalise_generated_template_definition(raw_definition)
			definition = Utils.safe_hash(raw_definition)
			if definition.key?('slugify')
				definition['slugify'] = normalise_slugify_config(definition['slugify'])
			end

			definition
		end

		# Returns site-level defaults that are inherited by explicit and
		# generated templates.
		def extract_site_template_defaults(site_config)
			source = Utils.safe_hash(site_config)
			defaults = template_setting_defaults

			template_setting_keys.each do |key|
				next unless source.key?(key)

				defaults[key] = Utils.deep_copy(source[key])
			end

			defaults
		end

		# Extracts template-level overrides from one `pagination` hash.
		#
		# Legacy nested aliases under `pagination.templates` remain supported
		# so older config still migrates correctly.
		def extract_template_defaults_overrides(raw_overrides)
			override_hash = Utils.safe_hash(raw_overrides)
			nested_template_overrides = Utils.safe_hash(override_hash['templates'])
			overrides = {}

			(template_setting_keys + legacy_template_alias_keys).each do |key|
				if override_hash.key?(key)
					overrides[key] = override_hash[key]
					next
				end

				next unless nested_template_overrides.key?(key)

				overrides[key] = nested_template_overrides[key]
			end

			overrides
		end

		# Normalises one template-default hash (used by site defaults and
		# by per-template runtime config).
		def normalise_template_defaults(template_defaults, raw_overrides:, split_delimiter:, keywords:)
			config = Jekyll::Utils.deep_merge_hashes(
				template_setting_defaults,
				Utils.safe_hash(template_defaults)
			)
			template_override_hash = extract_template_defaults_overrides(raw_overrides)
			sort_explicitly_set = template_override_hash.key?('sort') && present_config_value?(template_override_hash['sort'])
			config['sort_field'] = template_override_hash['sort_field'] if template_override_hash.key?('sort_field')
			config['sort_reverse'] = template_override_hash['sort_reverse'] if template_override_hash.key?('sort_reverse')
			config['indexpage'] = template_override_hash['indexpage'] if template_override_hash.key?('indexpage')
			config['extension'] = template_override_hash['extension'] if template_override_hash.key?('extension')

			config['items'] = normalise_items_value(config['items'])
			config['debug'] = !!config['debug']
			config['collection'] = normalise_collection_targets(
				config['collection'],
				split_delimiter: split_delimiter,
				keywords: keywords
			)
			config['filters'] = Utils.safe_hash(config['filters'])
			config['offset'] = [config['offset'].to_i, 0].max
			config['per_page'] = normalise_per_page(config['per_page'], split_delimiter: split_delimiter)
			config['limit'] = [config['limit'].to_i, 0].max
			config['permalink'] = config['permalink'].to_s
			config['title'] = config['title'].to_s
			config['trail'] = normalise_trail(config['trail'])
			config['sort'] = normalise_sort(
				config['sort'],
				config['sort_field'],
				config['sort_reverse'],
				split_delimiter,
				sort_explicitly_set: sort_explicitly_set
			)
			config['layouts'] = normalise_layout_overrides(config, split_delimiter: split_delimiter)
			group_source = normalise_legacy_group_source(config, split_delimiter: split_delimiter)
			config['group'] = normalise_group_entries(group_source, split_delimiter: split_delimiter)
			config['slugify'] = normalise_slugify_config(config['slugify'])
			config['page_templates'] = build_page_templates(config['title'], config['permalink'])

			config.delete('layout')
			config.delete('index')
			config.delete('filter')
			config.delete('sort_field')
			config.delete('sort_reverse')
			config.delete('indexpage')
			config.delete('extension')

			config
		end

		# Copies normalised template defaults back to the site-level config
		# so downstream code can consume canonical keys directly.
		def apply_template_defaults_to_site_config!(config, template_defaults)
			template_setting_keys.each do |key|
				config[key] = Utils.deep_copy(template_defaults[key])
			end
			config['page_templates'] = Utils.deep_copy(template_defaults['page_templates'])
			legacy_template_alias_keys.each { |legacy_key| config.delete(legacy_key) }
		end

		# Returns canonical keys that are inherited by all templates.
		def template_setting_keys
			@template_setting_keys ||= %w[items filters group sort debug per_page limit offset trail title permalink slugify collection layout].freeze
		end

		# Returns template-default keys that have v3 built-in defaults when
		# not configured globally.
		def template_setting_built_in_default_keys
			@template_setting_built_in_default_keys ||= %w[sort debug per_page limit offset trail title permalink slugify collection].freeze
		end

		# Returns legacy aliases that still map into template defaults.
		def legacy_template_alias_keys
			@legacy_template_alias_keys ||= %w[sort_field sort_reverse indexpage extension].freeze
		end

		# Returns deep-copied defaults for all template settings.
		def template_setting_defaults
			template_setting_built_in_default_keys.each_with_object({}) do |key, defaults|
				defaults[key] = Utils.deep_copy(DEFAULTS[key])
			end
		end

		# Normalises index destination config accepted on
		# `pagination.collection` (site defaults and template-level override).
		#
		# Accepts:
		# - String values (`self`, `shadow`, `clone`, `pages`, collection label)
		# - Arrays
		# - Delimited strings (using configured split delimiter)
		#
		# Returns an array with one or two canonical entries.
		def normalise_collection_targets(raw_collection, split_delimiter:, keywords:)
			default_targets = Utils.deep_copy(DEFAULTS['collection'])
			entries = Utils.delimited_array(raw_collection, delimiter: split_delimiter)
			return default_targets if entries.empty?

			normalised = entries.map do |entry|
				normalise_collection_target_entry(entry, keywords)
			end.reject { |entry| entry.to_s.empty? }

			normalised = Utils.deep_copy(default_targets) if normalised.empty?
			if normalised.length > 2
				raise ArgumentError, 'pagination.collection may contain at most two values.'
			end

			normalised
		end

		# Converts one collection target token into canonical runtime value.
		def normalise_collection_target_entry(raw_entry, keywords)
			entry = raw_entry.to_s.strip
			return '' if entry.empty?

			COLLECTION_TARGET_BY_KEY.each do |key, internal_target|
				keyword = keywords[key]
				next if keyword.to_s.empty?
				return internal_target if entry == keyword
			end

			entry
		end

		# Builds internal page template settings.
		#
		# Page 1 defaults to inheriting title/location from the source
		# template, while page 2+ uses configured paginator patterns.
		def build_page_templates(page2_title, page2_permalink)
			{
				'page1' => {
					'title' => '{{ title }}',
					'permalink' => ''
				},
				'page2' => {
					'title' => page2_title.to_s,
					'permalink' => page2_permalink.to_s
				}
			}
		end

		# Purpose: Normalises items value into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_items`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_items_value(raw_items)
			return nil if raw_items.nil?
			return nil if raw_items.is_a?(Hash) && raw_items.empty?
			return nil if raw_items.is_a?(Array) && raw_items.empty?
			return raw_items if raw_items.is_a?(Hash) || raw_items.is_a?(Array)

			value = raw_items.to_s.strip
			value.empty? ? nil : value
		end

		# Purpose: Normalises trail into canonical form.
		# Connects to: the surrounding pagination flow in this file.
		# Params: `raw_trail`.
		# Returns: a value consumed by the next pipeline step.
		def normalise_trail(raw_trail)
			if raw_trail.is_a?(Numeric) || raw_trail.to_s.match?(/\A-?\d+\z/)
				trail_size = [raw_trail.to_i, 0].max
				return {
					'before' => trail_size,
					'after' => trail_size
				}
			end

			trail = Utils.safe_hash(raw_trail)
			{
				'before' => [trail['before'].to_i, 0].max,
				'after' => [trail['after'].to_i, 0].max
			}
		end

		# Normalises per-page configuration.
		#
		# Accepts:
		# - Integer-like values
		# - Array values
		# - Delimited strings (using configured split delimiter)
		#
		# Returns either:
		# - Integer, for single-size pagination
		# - Array<Integer>, for variable per-page pagination patterns
		def normalise_per_page(raw_per_page, split_delimiter:)
			if raw_per_page.is_a?(Array)
				return Utils.normalise_per_page_pattern(raw_per_page)
			end

			if raw_per_page.is_a?(String)
				split_values = Utils.delimited_array(raw_per_page, delimiter: split_delimiter)
				if split_values.length > 1
					return Utils.normalise_per_page_pattern(split_values)
				end
			end

			Utils.normalise_per_page_pattern(raw_per_page).first
		end

		# Preserves legacy `sort_field` + `sort_reverse` behaviour when the
		# caller did not provide an explicit `sort` override.
		def normalise_sort(raw_sort, raw_sort_field, raw_sort_reverse, split_delimiter, sort_explicitly_set: false)
			sort_entries = placeholder_aware_sort_entries(raw_sort, split_delimiter)
			sort_field = raw_sort_field.to_s.strip

			if !sort_explicitly_set && !sort_field.empty?
				direction = boolean_config_value(raw_sort_reverse) ? 'desc' : 'asc'
				return ["#{sort_field} #{direction}"]
			end

			return sort_entries unless sort_entries.empty?

			if sort_field.empty?
				fallback_sort = DEFAULTS['sort']
				return placeholder_aware_sort_entries(fallback_sort, split_delimiter)
			end

			direction = boolean_config_value(raw_sort_reverse) ? 'desc' : 'asc'
			["#{sort_field} #{direction}"]
		end

		# Splits sort lists without treating a canonical placeholder filter pipe
		# as the configured list separator.
		def placeholder_aware_sort_entries(raw_sort, split_delimiter)
			raw_entries = raw_sort.is_a?(Array) ? raw_sort.flatten : [raw_sort]
			raw_entries.flat_map do |raw_entry|
				Support::PlaceholderTemplate.split_source(
					raw_entry,
					delimiter: split_delimiter
				)
			end.map(&:to_s).map(&:strip).reject(&:empty?)
		end

		# Normalises `pagination.layout` / `pagination.layouts` into a
		# canonical string array.
		def normalise_layout_overrides(config, split_delimiter:)
			Utils.normalise_layouts(config, split_delimiter: split_delimiter)
		end

		# Normalises template-level grouping definitions.
		#
		# Accepted forms:
		# - `group: category`
		# - `group: category,tag`
		# - `group: [{ on: 'size', size: 100 }, { on: 'tag' }]`
		# - `group: { on: 'size', size: { step: 100 } }`
		def normalise_group_entries(raw_group, split_delimiter:)
			return [] if raw_group.nil? || raw_group == false

			raw_entries = if raw_group.is_a?(Array)
								raw_group.flatten.compact
							elsif raw_group.is_a?(String)
								Utils.delimited_array(raw_group, delimiter: split_delimiter)
							elsif raw_group.is_a?(Hash)
								[raw_group]
							else
								[raw_group]
							end

			entries = raw_entries.map do |raw_entry|
				normalise_group_entry(raw_entry)
			end.compact

			keys = entries.map { |entry| entry['on'].to_s }
			duplicate_keys = keys.group_by(&:itself).select { |_, matches| matches.length > 1 }.keys
			unless duplicate_keys.empty?
				raise ArgumentError, "Duplicate pagination group key(s): #{duplicate_keys.sort.join(', ')}. Each `group.on` key must be unique."
			end

			entries
		end

		# Normalises legacy `index` + `group` + `filter` config into modern
		# `group` entry structures.
		def normalise_legacy_group_source(config, split_delimiter:)
			legacy_index_keys = Utils.delimited_array(config['index'], delimiter: split_delimiter).map { |entry| entry.to_s.strip }.reject(&:empty?)
			return config['group'] if legacy_index_keys.empty?

			legacy_group = config['group']
			legacy_filter = config['filter']
			legacy_group_hash = Utils.safe_hash(legacy_group)

			legacy_index_keys.map do |index_key|
				entry = { 'on' => index_key }
				legacy_size = if legacy_group_hash.empty?
									legacy_group
								elsif legacy_group_hash.key?(index_key)
									legacy_group_hash[index_key]
								elsif legacy_index_keys.length == 1
									legacy_group
								end
				entry['size'] = legacy_size if present_config_value?(legacy_size) && legacy_size != false
				entry['filter'] = legacy_filter if present_config_value?(legacy_filter)
				entry
			end
		end

		# Normalises one grouping entry.
		def normalise_group_entry(raw_entry)
			if raw_entry.is_a?(Hash)
				hash_entry = Utils.safe_hash(raw_entry)
				return nil if hash_entry.empty?

				if hash_entry.key?('on')
					on_key = hash_entry['on'].to_s.strip
					return nil if on_key.empty?

					normalised = { 'on' => on_key }
					raw_size = if hash_entry.key?('size')
									hash_entry['size']
								elsif hash_entry.key?('bunch')
									hash_entry['bunch']
								elsif hash_entry.key?('group')
									hash_entry['group']
								end
					normalised['size'] = raw_size if present_config_value?(raw_size)
					normalised['filter'] = hash_entry['filter'] if hash_entry.key?('filter')
					return normalised
				end

				if hash_entry.length == 1
					on_key = hash_entry.keys.first.to_s.strip
					return nil if on_key.empty?

					return {
						'on' => on_key,
						'size' => hash_entry.values.first
					}
				end

				return nil
			end

			on_key = raw_entry.to_s.strip
			return nil if on_key.empty?

			{ 'on' => on_key }
		end

		# Normalises slugify config into the route-key policy shared by grouping
		# and slugified placeholder representations.
		def normalise_slugify_config(raw_slugify)
			slugify = raw_slugify.is_a?(String) ? { 'mode' => raw_slugify } : Utils.safe_hash(raw_slugify)
			mode = slugify['mode'].to_s.strip
			mode = 'default' if mode.empty?
			unless SLUGIFY_MODES.include?(mode)
				raise ArgumentError, "`slugify.mode` must be one of #{SLUGIFY_MODES.join(', ')}; received '#{mode}'."
			end

			lowercase = if slugify.key?('lowercase')
								boolean_config_value(slugify['lowercase'])
							else
								true
							end

			{
				'mode' => mode,
				'lowercase' => lowercase
			}
		end

		# Coerces loose truthy/falsey config values to a strict boolean.
		def boolean_config_value(value)
			Jekyll::Plugins::PaginateV3::Support::LooseScalar.boolean(value) == true
		end

		# Migrates old v2 shorthand config into canonical template fields.
		# Modern keys retain precedence when both forms are supplied.
	end
end

end
end
end
end
