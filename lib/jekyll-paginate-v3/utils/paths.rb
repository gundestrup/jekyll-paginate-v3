# frozen_string_literal: true

require 'digest'
require 'uri'

module Jekyll
module Plugins
module PaginateV3

# URL and path normalisation helpers.
#
# Used by paginator/page generation code to keep output paths stable.
module Utils

	INVALID_RESOLVED_PERMALINK_CHARACTERS = /[\x00-\x20\x7f\\?#]/.freeze
	
	# Removes one leading slash from a path-like string.
	def self.remove_leading_slash(path)
		string_path = path.to_s
		string_path.start_with?('/') ? string_path[1..-1] : string_path
	end

	# Ensures a path-like string has a leading slash.
	def self.ensure_leading_slash(path)
		string_path = path.to_s
		string_path.start_with?('/') ? string_path : "/#{string_path}"
	end

	# Ensures a path-like string has a trailing slash.
	def self.ensure_trailing_slash(path)
		string_path = path.to_s
		string_path.end_with?('/') ? string_path : "#{string_path}/"
	end

	# Normalises one site-local route for comparison and public metadata.
	def self.normalise_route(route)
		value = ensure_leading_slash(route.to_s.strip)
		return '/' if value == '/'

		strip_trailing_characters(value, '/')
	end

	# Returns the route fragment added beneath a base route.
	#
	# Native V3 pagination outputs must remain descendants of their source
	# template so consumers can compose `pagination.base` and `.path`.
	def self.descendant_route_path(base_route, destination_route, context:)
		base = normalise_route(base_route)
		destination = normalise_route(destination_route)
		return '' if destination == base

		base_prefix = base == '/' ? '/' : "#{base}/"
		if destination.start_with?(base_prefix)
			return strip_trailing_characters(destination[base_prefix.length..-1].to_s, '/')
		end

		description = context.to_s.empty? ? 'pagination variant' : context.to_s
		raise ArgumentError, "Resolved route #{destination.inspect} for #{description} must remain beneath source template route #{base.inspect}."
	end

	# Joins already-resolved relative route fragments for public metadata.
	def self.join_route_fragments(*fragments)
		fragments.map do |fragment|
			strip_trailing_characters(fragment.to_s.strip.sub(%r{\A/+}, ''), '/')
		end.reject(&:empty?).join('/')
	end

	# Rejects root-relative permalink templates in native V3 configuration.
	def self.validate_relative_permalink_template!(permalink, context:)
		value = permalink.to_s.strip
		return value if value.empty? || !value.start_with?('/')

		description = context.to_s.empty? ? 'pagination permalink' : context.to_s
		raise ArgumentError, "Invalid #{description} #{value.inspect}: native V3 pagination permalinks must be relative to the source template; root-relative paths are supported only in v1 compatibility mode."
	end

	# Ensures a filename extension has a leading dot.
	def self.ensure_leading_dot(extension)
		string_extension = extension.to_s
		return '' if string_extension.empty?

		string_extension.start_with?('.') ? string_extension : ".#{string_extension}"
	end

	# Normalises a full path by appending a default filename and extension when needed.
	def self.ensure_full_path(path, default_index_name, default_extension)
		url = path.to_s
		extension = ensure_leading_dot(default_extension)
		index_name = default_index_name.to_s

		if url.end_with?('/')
			return "#{url}#{index_name}#{extension}"
		end

		return "#{url}#{extension}" if File.extname(url).empty?

		url
	end

	# Validates a fully interpolated permalink before Jekyll converts it into an
	# output destination. Encoded input is decoded repeatedly for structural
	# checks so nested escaping cannot conceal separators or traversal segments.
	def self.validate_resolved_permalink!(permalink, context:)
		value = permalink.to_s
		description = context.to_s.empty? ? 'pagination output' : context.to_s
		raise_invalid_permalink!(value, description, 'it is empty') if value.empty?
		raise_invalid_permalink!(value, description, 'it must be a site-local path beginning with /') unless value.start_with?('/')
		raise_invalid_permalink!(value, description, 'network-path references beginning with // are not allowed') if value.start_with?('//')
		raise_invalid_permalink!(value, description, 'URI schemes are not allowed') if value.include?('://')
		raise_invalid_permalink!(value, description, 'it contains whitespace, a control character, a backslash, a query marker, or a fragment marker') if value.match?(INVALID_RESOLVED_PERMALINK_CHARACTERS)

		value.split('/', -1).each do |segment|
			decoded_segment = fully_decode_permalink_segment(segment, permalink: value, context: description)
			if %w[. ..].include?(decoded_segment)
				raise_invalid_permalink!(value, description, "it contains the traversal segment #{decoded_segment.inspect}")
			end
			if decoded_segment.include?('/') || decoded_segment.include?('\\')
				raise_invalid_permalink!(value, description, 'an encoded path separator is not allowed')
			end
			if decoded_segment.match?(INVALID_RESOLVED_PERMALINK_CHARACTERS)
				raise_invalid_permalink!(value, description, 'an encoded unsafe character is not allowed')
			end
		end

		value
	end

	# Ensures the destination calculated by the generated Jekyll item stays
	# beneath the configured site destination directory.
	def self.validate_output_destination!(item, site:, context:)
		destination_root = File.expand_path(site.dest.to_s)
		output_path = File.expand_path(item.destination(destination_root).to_s)
		comparison_root = Gem.win_platform? ? destination_root.downcase : destination_root
		comparison_output = Gem.win_platform? ? output_path.downcase : output_path
		root_prefix = comparison_root.end_with?(File::SEPARATOR) ? comparison_root : "#{comparison_root}#{File::SEPARATOR}"
		return output_path if comparison_output == comparison_root || comparison_output.start_with?(root_prefix)

		raise ArgumentError, "Generated destination #{output_path.inspect} for #{context} falls outside site destination #{destination_root.inspect}."
	end

	# Builds one deterministic synthetic source path for in-memory pages
	# and documents. Filenames remain readable for debugging while a hash
	# suffix preserves practical uniqueness across templates and variants.
	def self.build_synthetic_source_path(site:, extension:, signature:, collection: nil, source_path: nil, source_stem: nil, role:, page_number: nil)
		directory = collection.nil? ? site.source : File.join(site.source, collection.relative_directory)
		File.join(
			directory,
			build_synthetic_filename(
				extension: extension,
				signature: signature,
				source_path: source_path,
				source_stem: source_stem,
				role: role,
				page_number: page_number
			)
		)
	end

	# Builds one readable synthetic filename from source identity plus a
	# deterministic safety suffix.
	def self.build_synthetic_filename(extension:, signature:, source_path: nil, source_stem: nil, role:, page_number: nil)
		stem = derive_synthetic_source_stem(source_path: source_path, source_stem: source_stem, fallback: role)
		filename_segments = [stem, role.to_s.strip]
		filename_segments << page_number.to_i.to_s unless page_number.nil?
		filename_segments << Digest::SHA256.hexdigest(canonical_signature(signature).inspect)[0, 32]
		"#{filename_segments.reject(&:empty?).join('-')}#{ensure_leading_dot(extension)}"
	end

	# Derives one human-readable synthetic stem from an original source
	# path or fallback label.
	def self.derive_synthetic_source_stem(source_path: nil, source_stem: nil, fallback: 'generated')
		candidate = extract_source_filename_stem(source_path)
		candidate = source_stem.to_s if candidate.empty?
		candidate = fallback.to_s if candidate.to_s.strip.empty?
		sanitise_filename_component(candidate, fallback: fallback)
	end

	# Derives one readable stem from frontmatter when no real source path
	# exists, preferring permalink and then title.
	def self.derive_synthetic_source_stem_from_frontmatter(frontmatter, fallback: 'generated')
		frontmatter_hash = safe_hash(frontmatter)
		permalink_stem = extract_permalink_stem(frontmatter_hash['permalink'])
		return derive_synthetic_source_stem(source_stem: permalink_stem, fallback: fallback) unless permalink_stem.empty?

		derive_synthetic_source_stem(source_stem: frontmatter_hash['title'], fallback: fallback)
	end

	# Extracts one source-style stem from a real path-like value.
	def self.extract_source_filename_stem(source_path)
		path = source_path.to_s
		return '' if path.strip.empty?

		File.basename(path, File.extname(path))
	end

	# Extracts one final path segment from a permalink-like value.
	def self.extract_permalink_stem(permalink)
		path = permalink.to_s.strip
		return '' if path.empty?

		segments = path.split('/').reject(&:empty?)
		return '' if segments.empty?

		File.basename(segments.last, File.extname(segments.last))
	end

	# Sanitises one filename component while preserving source readability
	# where the original stem is already filesystem-safe.
	def self.sanitise_filename_component(value, fallback: 'generated')
		component = value.to_s.strip
		component = component.gsub(%r{[\\/]}, '-')
		component = component.gsub(/[<>:"|?*\x00-\x1f]/, '-')
		component = component.gsub(/^-+/, '')
		component = strip_trailing_characters(component, '.', ' ')
		component = fallback.to_s if component.empty?
		component
	end

	# Canonicalises nested signature data so hashes with identical meaning
	# yield the same suffix regardless of insertion order.
	def self.canonical_signature(value)
		case value
		when Hash
			value.each_with_object({}) do |(key, nested_value), canonical|
				canonical[key.to_s] = canonical_signature(nested_value)
			end.sort_by { |key, _| key }.to_h
		when Array
			value.map { |entry| canonical_signature(entry) }
		else
			value
		end
	end

	# Removes trailing characters by walking backwards — linear time, unlike
	# end-anchored repetition patterns (`/+\z`, `[. ]+$`) which rescan the
	# run once per start position.
	def self.strip_trailing_characters(value, *characters)
		value = value.chop while value.end_with?(*characters)
		value
	end
	private_class_method :strip_trailing_characters

	# Decodes one URL segment until stable and rejects malformed percent escapes
	# exposed at any layer.
	def self.fully_decode_permalink_segment(segment, permalink:, context:)
		decoded = segment.to_s
		loop do
			if decoded.match?(/%(?![0-9A-Fa-f]{2})/)
				raise_invalid_permalink!(permalink, context, 'it contains an invalid percent escape')
			end

			next_decoded = URI::DEFAULT_PARSER.unescape(decoded)
			return decoded if next_decoded == decoded

			decoded = next_decoded
		end
	end
	private_class_method :fully_decode_permalink_segment

	# Raises one consistent resolved-permalink validation error.
	def self.raise_invalid_permalink!(permalink, context, reason)
		raise ArgumentError, "Invalid resolved permalink #{permalink.inspect} for #{context}: #{reason}."
	end
	private_class_method :raise_invalid_permalink!
end

end
end
end
