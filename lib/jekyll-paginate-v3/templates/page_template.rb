# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Generated pagination template page backed by in-memory frontmatter and
# content.
#
# Used by Templates::Builder for generated page-based templates.
class PageTemplate < Jekyll::Page
	# Creates an in-memory page that behaves like a hand-authored
	# pagination template.
	def initialize(site:, pagination_config:, frontmatter:, content:, generated_metadata:)
		@site = site
		@base = site.source
		@dir = '/'
		@name = 'index.html'
		@url = '/'
		@path = build_virtual_path(site, pagination_config, frontmatter, content)

		process(@name)

		generated_metadata_hash = Utils.safe_hash(generated_metadata)
		self.data = Utils.safe_hash(frontmatter)
		self.content = content.to_s
		self.data['pagination'] = Utils.safe_hash(pagination_config)
		self.data['pagination']['template'] = true
		self.data['paginate_v3'] = generated_metadata_hash

		apply_permalink!

		data.default_proc = proc do |_, key|
			site.frontmatter_defaults.find(relative_path, type, key)
		end
	end

	private

	# Builds a deterministic virtual source path for this synthetic page.
	def build_virtual_path(site, pagination_config, frontmatter, content)
		Utils.build_synthetic_source_path(
			site: site,
			extension: '.md',
			source_stem: Utils.derive_synthetic_source_stem_from_frontmatter(frontmatter, fallback: 'generated-template'),
			role: 'template',
			signature: {
				'pagination' => Utils.safe_hash(pagination_config),
				'frontmatter' => Utils.safe_hash(frontmatter),
				'content' => content.to_s,
				'content_type' => 'page-template'
			}
		)
	end

	# Applies frontmatter permalink directly so the synthetic template
	# lands at the intended route before pagination expansion.
	def apply_permalink!
		return unless data['permalink']

		permalink = data['permalink'].to_s
		@dir = permalink
		@url = Utils.ensure_full_path(permalink, 'index', '.html')
	end
end

end
end
end
end
