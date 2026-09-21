# frozen_string_literal: true

PlaceholderTemplateValue = Jekyll::Plugins::PaginateV3::Support::PlaceholderTemplate::Value

RSpec.describe Jekyll::Plugins::PaginateV3::Support::PlaceholderTemplate do
	def parse(source, allowed: %w[category num], allowed_filters: nil, unknown: described_class::UNKNOWN_ERROR)
		described_class.parse(
			source,
			allowed: allowed,
			context: 'spec pattern',
			allowed_filters: allowed_filters,
			unknown: unknown
		)
	end

	it 'resolves canonical placeholders with contextual defaults and explicit filters' do
		value = PlaceholderTemplateValue.new(raw: 'Old Shoes', slugified: 'old-shoes')
		pattern = parse('{{ category }} / {{ category | slugify }} / {{category | raw}}')

		expect(pattern.render({ 'category' => value }, default_representation: :raw)).to eq('Old Shoes / old-shoes / Old Shoes')
	end

	it 'lexes legacy placeholders greedily into the same resolver' do
		pattern = parse(':category-name/:category', allowed: %w[category category-name])
		value = PlaceholderTemplateValue.new(raw: 'short')
		long_value = PlaceholderTemplateValue.new(raw: 'long')

		expect(
			pattern.render(
				{ 'category' => value, 'category-name' => long_value },
				default_representation: :raw
			)
		).to eq('long/short')
	end

	it 'keeps bound values opaque during later path splitting' do
		value = PlaceholderTemplateValue.new(raw: 'old.shoes', slugified: 'old-shoes')
		bound = parse('details.{{ category | raw }}.name').bind(
			{ 'category' => value },
			default_representation: :slugify
		)

		expect(bound.split('.').map(&:to_s)).to eq(['details', 'old.shoes', 'name'])
	end

	it 'does not recursively interpret placeholder-looking bound values' do
		pattern = parse('{{ category }} {{ num }}')
		bound = pattern.bind(
			{ 'category' => PlaceholderTemplateValue.new(raw: ':num') },
			default_representation: :raw
		)

		expect(
			bound.render({ 'num' => PlaceholderTemplateValue.new(raw: 4) }, default_representation: :raw)
		).to eq(':num 4')
	end

	it 'rejects mixed canonical and recognised legacy syntax in one scalar' do
		expect do
			parse('{{ category }} on page :num')
		end.to raise_error(ArgumentError, /Cannot mix canonical/)
	end

	it 'rejects unsupported or repeated canonical filters' do
		expect do
			parse('{{ category | downcase }}')
		end.to raise_error(ArgumentError, /Unsupported placeholder filter/)

		expect do
			parse('{{ category | raw | slugify }}')
		end.to raise_error(ArgumentError, /at most one filter/)
	end

	it 'rejects every filter on numeric system placeholders' do
		%w[num max].product(described_class::FILTERS).each do |name, filter|
			expect do
				parse("{{ #{name} | #{filter} }}", allowed: %w[num max])
			end.to raise_error(ArgumentError, /Placeholder '#{name}' does not accept filters/)
		end
	end

	it 'enforces context-specific filters for metadata placeholders' do
		allowed_filters = { 'category' => ['slugify'] }
		pattern = parse('{{ category | slugify }}', allowed_filters: allowed_filters)

		expect(
			pattern.render({ 'category' => PlaceholderTemplateValue.new(raw: 'Old Shoes') }, default_representation: :slugify)
		).to eq('old-shoes')

		expect do
			parse('{{ category | raw }}', allowed_filters: allowed_filters)
		end.to raise_error(ArgumentError, /Placeholder 'category' cannot use the 'raw' filter/)
	end

	it 'preserves unknown Liquid output expressions in permissive content' do
		pattern = parse(
			'{{ page.title }} — {{ category }}',
			allowed: ['category'],
			unknown: described_class::UNKNOWN_PRESERVE
		)

		expect(
			pattern.render({ 'category' => PlaceholderTemplateValue.new(raw: 'Guides') }, default_representation: :raw)
		).to eq('{{ page.title }} — Guides')
	end

	it 'allows recognised canonical and legacy placeholders to be escaped as literals' do
		canonical = parse('\\{{ category }} and {{ category }}')
		legacy = parse('\\:category and :category')
		value = PlaceholderTemplateValue.new(raw: 'Guides')

		expect(canonical.render({ 'category' => value }, default_representation: :raw)).to eq('{{ category }} and Guides')
		expect(legacy.render({ 'category' => value }, default_representation: :raw)).to eq(':category and Guides')
	end

	it 'leaves placeholders inside Liquid raw and comment regions untouched' do
		pattern = parse(
			'{% raw %}{{ category }}{% endraw %}{% comment %}{{ category }}{% endcomment %} {{ category }}',
			allowed: ['category'],
			unknown: described_class::UNKNOWN_PRESERVE
		)

		expect(
			pattern.render({ 'category' => PlaceholderTemplateValue.new(raw: 'Guides') }, default_representation: :raw)
		).to eq('{% raw %}{{ category }}{% endraw %}{% comment %}{{ category }}{% endcomment %} Guides')
	end

	it 'rejects raw resolution when a slug represents multiple raw group values' do
		value = PlaceholderTemplateValue.new(raw: 'Old Shoes', slugified: 'old-shoes', raw_available: false)

		expect do
			parse('{{ category | raw }}').render({ 'category' => value }, default_representation: :slugify)
		end.to raise_error(ArgumentError, /multiple raw values with the same slug/)
	end

	it 'splits configured delimiters and whitespace only outside canonical expressions' do
		expect(
			described_class.split_source('details.{{ category | raw }}.name|title desc', delimiter: '|')
		).to eq(['details.{{ category | raw }}.name', 'title desc'])
		expect(
			described_class.split_whitespace('details.{{ category | raw }}.name desc empty:first')
		).to eq(['details.{{ category | raw }}.name', 'desc', 'empty:first'])
	end
end
