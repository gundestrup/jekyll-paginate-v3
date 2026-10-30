lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'jekyll-paginate-v3/version'

Gem::Specification.new do |spec|
	spec.name = 'jekyll-paginate-v3'
	spec.version = Jekyll::Plugins::PaginateV3::VERSION
	spec.authors = ['Convincible']
	spec.email = ['development@convincible.media']

	spec.summary = "Flexible, configurable pagination for Jekyll websites."
	spec.description = "Automatically creates pagination pages (page 1, page 2, etc.) for sets of pages or collection documents. Powerful configuration options include filtering or grouping by any frontmatter key."
	spec.homepage = 'https://github.com/ConvincibleMedia/jekyll-paginate-v3'
	spec.license = 'LGPL-3.0-or-later'

	spec.files = Dir['lib/**/*.rb'] + %w[readme.md]
	spec.require_paths = ['lib']

	spec.required_ruby_version = '>= 2.4.4'

	# Jekyll 3.8.x is unsupportable: it requires kramdown ~> 1.14 while the
	# current GFM parser and modern tooling need kramdown ~> 2.0, and it
	# predates Ruby 3 compatibility fixes. Jekyll 3.9.x is the tested floor.
	spec.add_dependency 'jekyll', '>= 3.9.0', '< 5.0'

	spec.add_development_dependency 'jekyll-test-harness', '= 0.1.0.alpha'
	# Liquid requires bigdecimal, which is a bundled (not default) gem since Ruby 3.4.
	spec.add_development_dependency 'bigdecimal', '~> 4.1'
	# Jekyll 3.x requires csv/base64 but does not declare them, and both left the
	# default gems in Ruby 3.4 — declare them so the Jekyll 3.x CI leg can run.
	spec.add_development_dependency 'csv', '~> 3.3'
	spec.add_development_dependency 'base64', '~> 0.3'
	# Jekyll's default Markdown configuration uses this converter during the integration suite, so declare it rather than relying on a global gem.
	spec.add_development_dependency 'kramdown-parser-gfm', '~> 1.1'
	spec.add_development_dependency 'debug', '~> 1.9'
	spec.add_development_dependency 'rspec', '~> 3.10'
	spec.add_development_dependency 'rubocop', '~> 1.63'
	spec.add_development_dependency 'simplecov', '~> 1.0'
	# Cobertura XML formatter — loaded only on CI (see spec_helper).
	spec.add_development_dependency 'simplecov-cobertura', '~> 4.0'
	spec.add_development_dependency 'rake', '~> 13.0'
	spec.add_development_dependency 'bundler-audit', '~> 0.9'
end
