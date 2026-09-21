# frozen_string_literal: true

require 'digest'

module Jekyll
module Plugins
module PaginateV3
module Templates

# Token and metadata helpers for generated template placeholders.
# Structure: title/permalink token maps are derived first, then metadata
# payloads are composed for generated templates and grouped levels.
class Builder

	private
	
	def build_token_maps(index_keys, entry, slugify_config:)
		values = Utils.safe_hash(entry['values'])
		token_values = Utils.safe_hash(entry['token_values'])

		title_tokens = {}
		permalink_tokens = {}
		compatibility_tokens = {}

		index_keys.each do |key|
			value = values[key]
			configured_token_values = Utils.safe_hash(token_values[key])
			slugified_value = slugify_value(value, slugify_config)

			title_tokens[key] = if configured_token_values.key?('title')
														configured_token_values['title'].to_s
													else
														slugified_value
													end
			permalink_tokens[key] = if configured_token_values.key?('permalink')
																configured_token_values['permalink'].to_s
															else
																slugified_value
															end
			compatibility_tokens[key] = slugified_value
		end

		apply_legacy_token_aliases!(title_tokens, index_keys)
		apply_legacy_token_aliases!(permalink_tokens, index_keys)
		apply_legacy_token_aliases!(compatibility_tokens, index_keys)

		{
			'title' => title_tokens,
			'permalink' => permalink_tokens,
			'compatibility' => compatibility_tokens
		}
	end

	# Applies v2 legacy token aliases (`:coll`, `:cat`, `:tag`) for
	# generated title/permalink placeholders.
	def apply_legacy_token_aliases!(token_map, index_keys)
		if @compatibility_mode == 'v2'
			if index_keys.include?('collection')
				token_map['coll'] = token_map['collection']
			end

			if index_keys.include?('category') || index_keys.include?('categories')
				token_map['cat'] = token_map['category'] || token_map['categories']
			end

			if index_keys.include?('tag') || index_keys.include?('tags')
				token_map['tag'] = token_map['tag'] || token_map['tags']
			end
		end
	end

	# Normalises slugify config accepted on `templates.generate[]`.
	# This uses `slugify.lowercase` to control case conversion.
	def normalise_slugify_config(raw_slugify)
		slugify = Utils.safe_hash(raw_slugify)
		mode = slugify['mode'].to_s.strip
		mode = 'default' if mode.empty?

		lowercase = normalise_boolean(slugify['lowercase'])

		{
			'mode' => mode,
			'lowercase' => lowercase
		}
	end

	# Slugifies one token value according to an index definition.
	def slugify_value(value, slugify_config)
		mode = slugify_config['mode']
		lowercase = slugify_config['lowercase']
		Jekyll::Utils.slugify(value.to_s, mode: mode, cased: !lowercase)
	end

	# Coerces loose truthy/falsey config values to a strict boolean.
	def normalise_boolean(value)
		Jekyll::Plugins::PaginateV3::Support::LooseScalar.boolean(value) == true
	end

	# Captures generated-template metadata for compatibility and template use.
	def build_generated_metadata(index_keys, raw_values, token_map, group_levels: [])
		metadata = {
			'generated_template' => true,
			'index_keys' => index_keys,
			'tokens' => Utils.deep_copy(raw_values),
			'compatibility' => @compatibility_mode
		}

		if @compatibility_mode == 'v2' && index_keys.length == 1
			key = index_keys.first
			metadata['autopages'] = {
				'key' => key,
				'value' => token_map[key],
				'display_name' => raw_values[key].to_s
			}
		end

		unless group_levels.empty?
			metadata['groups'] = Utils.deep_copy(group_levels)
		end

		metadata
	end

	# Builds metadata for group-link sets at each indexed key depth.
	def build_group_level_metadata(entry, definition_number, layout_name)
		levels = Utils.arrayify(entry['levels'])
		return [] if levels.empty?

		levels.each_with_index.map do |level, depth|
			key = level['key'].to_s
			prefix_levels = levels.first(depth)
			prefix_signature = prefix_levels.map do |prefix_level|
				prefix_key = prefix_level['key'].to_s
				prefix_value = entry.dig('values', prefix_key).to_s
				"#{prefix_key}=#{prefix_value}"
			end.join('|')

			set_signature = [definition_number, layout_name, depth, key, prefix_signature].join('|')
			set_id = "generated-index-set-#{Digest::SHA256.hexdigest(set_signature)[0, 32]}"

			{
				'set_id' => set_id,
				'depth' => depth + 1,
				'key' => key,
				'order' => level['order'].to_i,
				'start' => level['start'],
				'end' => level['end'],
				'other' => !!level['other'],
				'range' => !!level['range']
			}
		end
	end

	# Adds synthetic entries for empty collections when `allow_empty` is enabled
	# on a single-level `collection` index definition.
	def add_empty_collection_entries(entries, definition)
		return entries unless definition['allow_empty']
		unless definition['index'] == ['collection']
			@log_lambda.call("`allow_empty` is only applicable for `index: collection`; skipping for index=#{describe_index_keys(definition['index'])}.", 'warn')
			return entries
		end

		expected_labels = expected_collection_labels(definition['items'])
		existing_labels = entries.map { |entry| entry.dig('values', 'collection').to_s }.reject(&:empty?).uniq
		added = 0

		expected_labels.each do |collection_label|
			next if existing_labels.include?(collection_label)
			next unless @site.collections.key?(collection_label)
			next unless @site.collections[collection_label].docs.empty?

			entries << {
				'filters' => { 'collection' => collection_label },
				'values' => { 'collection' => collection_label },
				'token_values' => {},
				'levels' => [
					{
						'key' => 'collection',
						'order' => entries.length + 1,
						'start' => collection_label,
						'end' => nil,
						'other' => false,
						'range' => false
					}
				]
			}
			added += 1
		end

		@log_lambda.call("Added #{added} empty collection index entry/entries.", 'debug') if added.positive?
		entries
	end

	# Determines which collections are targeted by an `items` search definition.
	def expected_collection_labels(raw_items)
		labels = []
		Query::Parser.parse(raw_items, @site_config['keywords'], split_delimiter: @split_delimiter).each do |entry|
			case entry['type']
			when Query::Parser::SEARCH_TYPE_ALL, Query::Parser::SEARCH_TYPE_EVERYTHING
				labels.concat(@site.collections.keys)
			when Query::Parser::SEARCH_TYPE_PAGES
				# pages do not map to collections
			else
				labels << entry['type'] if @site.collections.key?(entry['type'])
			end
		end

		labels.uniq
	end
end

end
end
end
end
