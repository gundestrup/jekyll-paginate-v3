# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Config::Normaliser do
	describe '.normalise_site_config' do
		it 'coerces boundary values and falls back to safe defaults' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => 'yes',
					'syntax' => {
						'split' => nil,
						'separator' => ''
					},
					'templates' => {
						'location' => '',
						'generate' => {
							'items' => 'posts'
						},
						'per_page' => 0,
						'offset' => -5,
						'limit' => -3
					}
				}
			)

			expect(config['enabled']).to eq(true)
			expect(config['per_page']).to eq(1)
			expect(config['offset']).to eq(0)
			expect(config['limit']).to eq(0)
			expect(config.dig('syntax', 'split')).to eq(',')
			expect(config.dig('syntax', 'separator')).to eq('.')
			expect(config.dig('keywords', 'now')).to eq('now')
			expect(config.dig('keywords', 'today')).to eq('today')
			expect(config.dig('templates', 'location')).to eq('pages')
			expect(config['collection']).to eq([
				Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_SELF,
				Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_SHADOW
			])
			expect(config.dig('templates', 'generate')).to be_an(Array)
			expect(config.dig('templates', 'generate').length).to eq(1)
		end

		it 'supports disabling global split parsing with syntax.split false' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'syntax' => {
						'split' => false
					}
				}
			)

			expect(config.dig('syntax', 'split')).to eq(false)
		end

		it 'uses sort_field and sort_reverse when sort is omitted' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'sort' => nil,
					'sort_field' => 'title',
					'sort_reverse' => true
				}
			)

			expect(config['sort']).to eq(['title desc'])
		end

		it 'supports variable per-page definitions as arrays' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'per_page' => [3, 1, 0, -4]
				}
			)

			expect(config['per_page']).to eq([3, 1, 1, 1])
		end

		it 'supports variable per-page definitions as delimited strings' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'syntax' => {
						'split' => '|'
					},
					'per_page' => '4|2|1'
				}
			)

			expect(config['per_page']).to eq([4, 2, 1])
		end

		it 'normalises delimited equivalent groups with a custom split delimiter' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'syntax' => {
						'split' => '|'
					},
					'equivalents' => 'tag|tags'
				}
			)

			expect(config['equivalents']).to eq([%w[tag tags]])
		end

		it 'supports nested_key_separator as a legacy alias for syntax.separator' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'nested_key_separator' => ':',
					'sort_field' => 'author:name'
				}
			)

			expect(config.dig('syntax', 'separator')).to eq(':')
			expect(config['sort']).to eq(['author:name asc'])
		end

		it 'rejects keyword values that are not lowercase latin tokens' do
			expect do
				described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'keywords' => {
							'now' => 'second-now'
						}
					}
				)
			end.to raise_error(ArgumentError, /must match \[a-z\]\+/)
		end

		it 'rejects duplicate keyword values' do
			expect do
				described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'keywords' => {
							'day' => 'window',
							'month' => 'window'
						}
					}
				)
			end.to raise_error(ArgumentError, /must be unique/)
		end

		it 'migrates v2 legacy filter shortcuts without overriding explicit filters' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'compatibility' => 'v2',
					'items' => 'products',
					'collection' => 'pages',
					'category' => 'featured',
					'tag' => 'legacy-tag',
					'filters' => {
						'category' => 'explicit-category'
					}
				}
			)

			expect(config['items']).to eq('products')
			expect(config['collection']).to eq([Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_PAGES])
			expect(config['filters']).to include(
				'category' => 'explicit-category',
				'tag' => 'legacy-tag'
			)
			expect(config).not_to have_key('category')
			expect(config).not_to have_key('tag')
		end

		it 'ignores the v2 legacy category shortcut when category is posts' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'compatibility' => 'v2',
					'category' => 'posts'
				}
			)

			expect(config['filters']).not_to have_key('category')
		end

		it 'migrates v2 autopages groups into templates.generate definitions' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'compatibility' => 'v2'
				},
				'autopages' => {
					'enabled' => true,
					'categories' => {
						'enabled' => true,
						'layouts' => 'category-a.html,category-b.html',
						'title' => 'Category :cat'
					},
					'collections' => {
						'enabled' => true
					}
				}
			)

			categories_definition = config.dig('templates', 'generate').find { |entry| entry['group'] == 'category' }
			collections_definition = config.dig('templates', 'generate').find { |entry| entry['group'] == 'collection' }

			expect(categories_definition).not_to be_nil
			expect(categories_definition['layouts']).to eq(%w[category-a.html category-b.html])
			expect(categories_definition.dig('frontmatter', 'title')).to eq('Category :cat')
			expect(categories_definition['items']).to eq('collections')
			expect(categories_definition).not_to have_key('silent')

			expect(collections_definition).not_to be_nil
			expect(collections_definition['layouts']).to eq(['autopage_collection.html'])
			expect(collections_definition['items']).to eq('collections')
		end

		it 'normalises collection targets from delimited strings' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'collection' => 'pages,clone'
				}
			)

			expect(config['collection']).to eq([
				Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_PAGES,
				Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_CLONE
			])
		end

		it 'promotes legacy nested template defaults to top-level defaults' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'collection' => 'pages',
						'per_page' => 4
					}
				}
			)

			expect(config['collection']).to eq([Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_PAGES])
			expect(config['per_page']).to eq(4)
		end

		it 'rejects collection target lists longer than two entries' do
			expect do
				described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'collection' => 'pages,self,shadow'
					}
				)
			end.to raise_error(ArgumentError, /at most two values/)
		end

		it 'supports custom collection keywords through pagination.keywords' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'keywords' => {
						'self' => 'same',
						'shadow' => 'mask'
					},
					'collection' => 'same,mask'
				}
			)

			expect(config['collection']).to eq([
				Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_SELF,
				Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_SHADOW
			])
		end

		it 'uses only renamed collection-mode keywords and releases their former collection labels' do
			keyword_aliases = {
				'pages' => 'sitepages',
				'self' => 'sourcecollection',
				'shadow' => 'hiddenpage',
				'clone' => 'copiedcollection'
			}

			keyword_aliases.each do |keyword, alternative|
				aliased_config = described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'keywords' => keyword_aliases,
						'collection' => alternative
					}
				)
				released_config = described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'keywords' => keyword_aliases,
						'collection' => keyword
					}
				)

				expect(aliased_config['collection']).to eq([Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_BY_KEY.fetch(keyword)])
				expect(released_config['collection']).to eq([keyword])
			end
		end

		it 'normalises group shorthand and slugify mode shorthand' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'group' => 'category,author.name',
					'slugify' => 'ascii'
				}
			)

			expect(config['group']).to eq([
				{ 'on' => 'category' },
				{ 'on' => 'author.name' }
			])
			expect(config['slugify']).to eq({ 'mode' => 'ascii', 'lowercase' => true })
		end

		it 'rejects slugify modes that do not produce supported route keys' do
			%w[none raw pretty misspelt].each do |mode|
				expect do
					described_class.normalise_site_config(
						'pagination' => {
							'enabled' => true,
							'slugify' => mode
						}
					)
				end.to raise_error(ArgumentError, /`slugify\.mode` must be one of default, ascii, latin; received '#{mode}'/)
			end
		end

		it 'normalises and validates generated-template slugify config immediately' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'generate' => {
							'group' => 'category',
							'slugify' => { 'mode' => 'latin' }
						}
					}
				}
			)

			expect(config.dig('templates', 'generate', 0, 'slugify')).to eq({ 'mode' => 'latin', 'lowercase' => true })

			expect do
				described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'templates' => {
							'generate' => {
								'group' => 'category',
								'slugify' => 'pretty'
							}
						}
					}
				)
			end.to raise_error(ArgumentError, /received 'pretty'/)
		end

		it 'supports legacy root split and separator aliases for syntax' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'split' => '|',
					'separator' => ':'
				}
			)

			expect(config.dig('syntax', 'split')).to eq('|')
			expect(config.dig('syntax', 'separator')).to eq(':')
		end

		it 'falls back to nested_key_separator when syntax.separator is blank' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'syntax' => {
						'separator' => '',
						'nested_key_separator' => ':'
					}
				}
			)

			expect(config.dig('syntax', 'separator')).to eq(':')
		end

		it 'passes unrecognised compatibility modes through without applying a profile' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'compatibility' => 'v9'
				}
			)

			expect(config['compatibility']).to eq('v9')
		end

		it 'derives sort from sort_field and sort_reverse when sort is set but blank' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'sort' => '',
					'sort_field' => 'date',
					'sort_reverse' => true
				}
			)

			expect(config['sort']).to eq(['date desc'])
		end

		it 'falls back to the default sort when sort and sort_field are both blank' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'sort' => '',
					'sort_field' => ''
				}
			)

			expect(config['sort']).to eq(['date desc'])
		end

		it 'restores default equivalents when equivalents is explicitly nil' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'equivalents' => nil
				}
			)

			expect(config['equivalents']).to eq([%w[tag tags], %w[category categories]])
		end

		it 'ignores generated-template definitions of unsupported types' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'generate' => 'nonsense'
					}
				}
			)

			expect(config.dig('templates', 'generate')).to eq([])
		end

		it 'supports single-key hash group entries and bunch/group size aliases' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'group' => [
						{ 'category' => 10 },
						{ 'on' => 'tag', 'bunch' => 3 },
						{ 'on' => 'author', 'group' => 4 },
						5,
						{ 'size' => 9, 'other' => 2 }
					]
				}
			)

			expect(config['group']).to eq([
				{ 'on' => 'category', 'size' => 10 },
				{ 'on' => 'tag', 'size' => 3 },
				{ 'on' => 'author', 'size' => 4 },
				{ 'on' => '5' }
			])
		end
	end

	describe '.normalise_template_config' do
		it 'supports nested_key_separator as a template-level syntax alias' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'collection' => 'clone,pages',
					'nested_key_separator' => ':',
					'filters' => {
						'author:name' => 'Alice'
					}
				}
			)

			expect(config['separator']).to eq(':')
			expect(config['collection']).to eq([
				Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_CLONE,
				Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_PAGES
			])
			expect(config.dig('filters', 'author:name')).to eq('Alice')
		end

		it 'inherits site-level debug defaults' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'debug' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'items' => 'posts'
				}
			)

			expect(site_config['debug']).to eq(true)
			expect(config['debug']).to eq(true)
		end

		it 'allows template-level debug to override the inherited default' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'debug' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'items' => 'posts',
					'debug' => false
				}
			)

			expect(config['debug']).to eq(false)
		end

		it 'inherits site-level defaults and allows template overrides' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'items' => 'products',
					'per_page' => 3,
					'collection' => 'pages',
					'slugify' => {
						'mode' => 'ascii',
						'case' => true
					}
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'items' => 'posts',
					'group' => [
						{ 'on' => 'size', 'size' => 100, 'filter' => { 'min' => 10 } },
						'tag'
					],
					'slugify' => 'latin'
				}
			)

			expect(config['items']).to eq('posts')
			expect(config['per_page']).to eq(3)
			expect(config['collection']).to eq([Jekyll::Plugins::PaginateV3::Config::COLLECTION_TARGET_PAGES])
			expect(config['group']).to eq([
				{ 'on' => 'size', 'size' => 100, 'filter' => { 'min' => 10 } },
				{ 'on' => 'tag' }
			])
			expect(config['slugify']).to eq({ 'mode' => 'latin', 'lowercase' => true })
		end

		it 'rejects duplicate normalised group keys' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'items' => 'posts'
				}
			)

			expect do
				described_class.normalise_template_config(
					site_config,
					{
						'group' => [' meta.category ', { 'on' => 'meta.category' }]
					}
				)
			end.to raise_error(ArgumentError, /Duplicate pagination group key.*meta\.category/)
		end

		it 'supports legacy split and separator keys on templates' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'split' => ';',
					'separator' => ':'
				}
			)

			expect(config['split']).to eq(';')
			expect(config['separator']).to eq(':')
		end

		it 'keeps the site separator when the template separator is blank' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'separator' => '   '
				}
			)

			expect(config['separator']).to eq('.')
		end

		it 'normalises legacy index, group, and filter keys into group entries' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'index' => 'category,tag',
					'group' => { 'category' => 5 },
					'filter' => { 'min' => 1 }
				}
			)

			expect(config['group']).to eq([
				{ 'on' => 'category', 'size' => 5, 'filter' => { 'min' => 1 } },
				{ 'on' => 'tag', 'filter' => { 'min' => 1 } }
			])
			expect(config).not_to have_key('index')
			expect(config).not_to have_key('filter')
		end

		it 'applies a scalar legacy group size to a single index key' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'index' => 'category',
					'group' => 10
				}
			)

			expect(config['group']).to eq([{ 'on' => 'category', 'size' => 10 }])
		end

		it 'reads nested legacy template overrides inside a template pagination block' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'templates' => {
						'sort_field' => 'date',
						'sort_reverse' => true
					}
				}
			)

			expect(config['sort']).to eq(['date desc'])
		end
	end
end
