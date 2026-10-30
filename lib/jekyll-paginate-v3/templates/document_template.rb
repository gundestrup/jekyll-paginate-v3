# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Generated pagination template document for collection-based template
# locations.
#
# Used by Templates::Builder for generated collection-document
# templates.
class DocumentTemplate < Jekyll::Document
	alias_method :ext, :extname

	# Creates an in-memory collection document seeded from frontmatter and
	# content supplied by generate config.
	def initialize(site:, collection:, pagination_config:, frontmatter:, content:, generated_metadata:)
		virtual_path = build_virtual_path(site, collection, pagination_config, frontmatter, content)
		generated_metadata_hash = Utils.safe_hash(generated_metadata)

		initialise_document(site, collection, virtual_path)

		merge_data!(Utils.safe_hash(frontmatter))
		self.content = content.to_s
		self.data['pagination'] = Utils.safe_hash(pagination_config)
		self.data['pagination']['template'] = true
		self.data['paginate_v3'] = generated_metadata_hash

		trigger_hooks(:post_init)
	end

	private

	# Builds a deterministic synthetic source path inside destination
	# collection.
	def build_virtual_path(site, collection, pagination_config, frontmatter, content)
		Utils.build_synthetic_source_path(
			site: site,
			collection: collection,
			extension: '.md',
			source_stem: Utils.derive_synthetic_source_stem_from_frontmatter(frontmatter, fallback: collection.label),
			role: 'template',
			signature: {
				'collection' => collection.label.to_s,
				'pagination' => Utils.safe_hash(pagination_config),
				'frontmatter' => Utils.safe_hash(frontmatter),
				'content' => content.to_s,
				'content_type' => 'document-template'
			}
		)
	end

	# Initialises minimal Jekyll::Document state for a synthetic doc.
	def initialise_document(site, collection, path)
		@site = site
		@path = path
		@collection = collection
		@type = @collection.label.to_sym
		@has_yaml_header = nil
		@extname = '.md'

		if draft?
			categories_from_path('_drafts')
		else
			categories_from_path(collection.relative_directory)
		end

		data.default_proc = proc do |_, key|
			site.frontmatter_defaults.find(relative_path, type, key)
		end
	end
end

end
end
end
end
