# frozen_string_literal: true

SorterTestCollection = Struct.new(:label)
SorterTestItem = Struct.new(:data, :collection)

RSpec.describe Jekyll::Plugins::PaginateV3::Query::Sorter do
	# Builds a minimal item object compatible with sorter evaluation.
	def build_item(data, collection: nil)
		collection_object = collection.nil? ? nil : SorterTestCollection.new(collection)
		SorterTestItem.new(data, collection_object)
	end

	# Runs the sorter with stable defaults used across examples.
	def apply_sort(items, sort_definition, split_delimiter: ',')
		described_class.apply(
			items,
			sort_definition,
			nested_separator: '.',
			equivalents: [%w[tag tags]],
			split_delimiter: split_delimiter
		)
	end

	it 'preserves input order when all sort keys tie' do
		items = [
			build_item({ 'title' => 'First', 'priority' => 1 }),
			build_item({ 'title' => 'Second', 'priority' => 1 }),
			build_item({ 'title' => 'Third', 'priority' => 1 })
		]

		sorted = apply_sort(items, 'priority asc')
		expect(sorted).to eq(items)
	end

	it 'orders mixed scalar types by rank before value comparison' do
		items = [
			build_item({ 'value' => 'alpha' }),
			build_item({ 'value' => 2 }),
			build_item({ 'value' => false }),
			build_item({ 'value' => true })
		]

		sorted = apply_sort(items, 'value asc')
		expect(sorted.map { |item| item.data['value'] }).to eq([true, false, 2, 'alpha'])
	end

	it 'places empty values first when configured' do
		items = [
			build_item({ 'title' => 'Bob', 'owner' => { 'name' => 'Bob' } }),
			build_item({ 'title' => 'No Owner' }),
			build_item({ 'title' => 'Ada', 'owner' => { 'name' => 'Ada' } })
		]

		sorted = apply_sort(items, 'owner.name asc empty:first')
		expect(sorted.map { |item| item.data['title'] }).to eq(['No Owner', 'Ada', 'Bob'])
	end

	it 'supports sorting by the synthetic collection field' do
		items = [
			build_item({ 'title' => 'Site Page' }),
			build_item({ 'title' => 'Product' }, collection: 'products'),
			build_item({ 'title' => 'Guide' }, collection: 'guides')
		]

		sorted = apply_sort(items, ['collection asc', 'title asc'])
		expect(sorted.map { |item| item.data['title'] }).to eq(['Guide', 'Product', 'Site Page'])
	end

	it 'parses delimited sort strings with a custom split delimiter' do
		instructions = described_class.parse('priority desc|title asc', split_delimiter: '|')

		expect(instructions).to eq(
			[
				{ 'field' => 'priority', 'direction' => 'desc', 'empty' => 'last' },
				{ 'field' => 'title', 'direction' => 'asc', 'empty' => 'last' }
			]
		)
	end

	it 'resolves canonical group placeholders to slugified structural paths' do
		items = [
			build_item({ 'title' => 'Second', 'details' => { 'old-shoes' => { 'name' => 'Zulu' } } }),
			build_item({ 'title' => 'First', 'details' => { 'old-shoes' => { 'name' => 'Alpha' } } })
		]
		group_value = Jekyll::Plugins::PaginateV3::Support::PlaceholderTemplate::Value.new(
			raw: 'Old Shoes',
			slugified: 'old-shoes'
		)
		instructions = described_class.parse(
			'details.{{ category }}.name asc',
			nested_separator: '.',
			group_keys: ['category'],
			group_values: { 'category' => group_value },
			structural: true
		)

		sorted = described_class.apply(
			items,
			nil,
			nested_separator: '.',
			equivalents: [],
			instructions: instructions
		)

		expect(instructions.first['field_segments']).to eq(%w[details old-shoes name])
		expect(sorted.map { |item| item.data['title'] }).to eq(%w[First Second])
	end

	it 'keeps a raw group value containing the path separator atomic' do
		items = [
			build_item({ 'title' => 'Second', 'details' => { 'old.shoes' => { 'name' => 'Zulu' } } }),
			build_item({ 'title' => 'First', 'details' => { 'old.shoes' => { 'name' => 'Alpha' } } })
		]
		group_value = Jekyll::Plugins::PaginateV3::Support::PlaceholderTemplate::Value.new(
			raw: 'old.shoes',
			slugified: 'old-shoes'
		)
		instructions = described_class.parse(
			'details.{{ category | raw }}.name asc',
			nested_separator: '.',
			group_keys: ['category'],
			group_values: { 'category' => group_value },
			structural: true
		)

		sorted = described_class.apply(
			items,
			nil,
			nested_separator: '.',
			equivalents: [],
			instructions: instructions
		)

		expect(instructions.first['field_segments']).to eq(['details', 'old.shoes', 'name'])
		expect(sorted.map { |item| item.data['title'] }).to eq(%w[First Second])
	end

	it 'allows only exact active group keys as sort placeholders' do
		expect do
			described_class.validate_placeholders!(
				'details.{{ category }}.name',
				group_keys: ['data.meta.category']
			)
		end.to raise_error(ArgumentError, /Unknown placeholder 'category'/)
	end

	it 'accepts greedy legacy group placeholders through the structural pipeline' do
		group_value = Jekyll::Plugins::PaginateV3::Support::PlaceholderTemplate::Value.new(
			raw: 'Old Shoes',
			slugified: 'old-shoes'
		)
		instructions = described_class.parse(
			'details.:category.name asc',
			nested_separator: '.',
			group_keys: ['category'],
			group_values: { 'category' => group_value },
			structural: true
		)

		expect(instructions.first['field_segments']).to eq(%w[details old-shoes name])
	end
end
