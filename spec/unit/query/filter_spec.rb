# frozen_string_literal: true

FilterTestCollection = Struct.new(:label)
FilterTestItem = Struct.new(:data, :collection, :path)

RSpec.describe Jekyll::Plugins::PaginateV3::Query::Filter do
	# Builds a minimal item object compatible with filter evaluation.
	def build_item(data, collection: nil, path: nil)
		collection_object = collection.nil? ? nil : FilterTestCollection.new(collection)
		FilterTestItem.new(data, collection_object, path)
	end

	# Runs the filter engine with stable defaults used across examples.
	def apply_filters(items, filters, now_keyword: 'now', today_keyword: 'today', split_delimiter: ',', log_lambda: nil, context_label: nil)
		described_class.filter_items(
			items,
			filters,
			nested_separator: '.',
			equivalents: [%w[tag tags]],
			split_delimiter: split_delimiter,
			now_keyword: now_keyword,
			today_keyword: today_keyword,
			log_lambda: log_lambda,
			context_label: context_label
		)
	end

	it 'ignores invalid filter definitions instead of failing closed' do
		items = [
			build_item({ 'title' => 'One', 'category' => 'news' }),
			build_item({ 'title' => 'Two', 'category' => 'blog' })
		]

		filtered = apply_filters(items, { 'category' => { 'unsupported' => 'value' } })
		expect(filtered).to eq(items)
	end

	it 'logs a warning when a filter definition is invalid' do
		logger = double('logger', call: nil)
		items = [
			build_item({ 'title' => 'One', 'category' => 'news' }, path: '_posts/one.md')
		]

		filtered = apply_filters(
			items,
			{ 'category' => { 'unsupported' => 'value' } },
			log_lambda: logger.method(:call),
			context_label: "Template 'index.md'"
		)

		expect(filtered).to eq(items)
		expect(logger).to have_received(:call).with(
			a_string_including("Template 'index.md': Ignoring invalid filter for key='category'"),
			'warn'
		)
	end

	it 'logs detailed debug diagnostics for key-level filtering decisions' do
		logger = double('logger', call: nil)
		items = [
			build_item({ 'title' => 'One', 'category' => 'news' }, path: '_posts/one.md'),
			build_item({ 'title' => 'Two', 'category' => 'blog' }, path: '_posts/two.md'),
			build_item({ 'title' => 'Three' }, path: '_posts/three.md')
		]

		filtered = apply_filters(
			items,
			{ 'category' => 'news' },
			log_lambda: logger.method(:call),
			context_label: "Template 'index.md'"
		)

		expect(filtered).to eq([items.first])
		expect(logger).to have_received(:call).with(
			a_string_including("Template 'index.md': Filter key='category'"),
			'debug'
		).at_least(:once)
		expect(logger).to have_received(:call).with(
			a_string_including("Filter key='category' missing key/value on: _posts/three.md"),
			'debug'
		)
		expect(logger).to have_received(:call).with(
			a_string_including("Filter key='category' excluded item sample: _posts/two.md=\"blog\""),
			'debug'
		)
	end

	it 'distinguishes strict and auto scalar matching for array values' do
		items = [
			build_item({ 'title' => 'One', 'tags' => %w[ruby jekyll] }),
			build_item({ 'title' => 'Two', 'tags' => ['jekyll'] })
		]

		strict_result = apply_filters(
			items,
			{
				'tags' => {
					'match' => 'ruby',
					'mode' => 'strict',
					'split' => false
				}
			}
		)
		auto_result = apply_filters(
			items,
			{
				'tags' => {
					'match' => 'ruby',
					'mode' => 'auto',
					'split' => false
				}
			}
		)

		expect(strict_result).to eq([])
		expect(auto_result).to eq([items.first])
	end

	it 'treats nested multi-value matches as array values for scalar modes' do
		items = [
			build_item({ 'title' => 'One', 'authors' => [{ 'name' => 'ruby' }, { 'name' => 'jekyll' }] }),
			build_item({ 'title' => 'Two', 'authors' => [{ 'name' => 'ruby' }] }),
			build_item({ 'title' => 'Three', 'authors' => [{ 'name' => 'jekyll' }] })
		]

		strict_result = apply_filters(
			items,
			{
				'authors.name' => {
					'match' => 'ruby',
					'mode' => 'strict',
					'split' => false
				}
			}
		)
		auto_result = apply_filters(
			items,
			{
				'authors.name' => {
					'match' => 'ruby',
					'mode' => 'auto',
					'split' => false
				}
			}
		)
		only_result = apply_filters(
			items,
			{
				'authors.name' => {
					'match' => 'ruby',
					'mode' => 'only',
					'split' => false
				}
			}
		)

		expect(strict_result).to eq([items[1]])
		expect(auto_result).to eq([items[0], items[1]])
		expect(only_result).to eq([items[1]])
	end

	it 'applies first-mode matching using the configured first count' do
		items = [
			build_item({ 'title' => 'One', 'contributors' => %w[alice bob] }),
			build_item({ 'title' => 'Two', 'contributors' => %w[bob alice] }),
			build_item({ 'title' => 'Three', 'contributors' => ['carol'] })
		]

		filtered = apply_filters(
			items,
			{
				'contributors' => {
					'match' => 'alice',
					'mode' => 'first(1)',
					'split' => false
				}
			}
		)

		expect(filtered).to eq([items.first])
	end

	it 'supports first(N) mode shorthand and defaults first to first(1)' do
		items = [
			build_item({ 'title' => 'One', 'contributors' => %w[alice bob] }),
			build_item({ 'title' => 'Two', 'contributors' => %w[bob alice] })
		]

		first_two = apply_filters(
			items,
			{
				'contributors' => {
					'match' => 'alice',
					'mode' => 'first(2)',
					'split' => false
				}
			}
		)
		first_one = apply_filters(
			items,
			{
				'contributors' => {
					'match' => 'alice',
					'mode' => 'first',
					'split' => false
				}
			}
		)

		expect(first_two).to eq(items)
		expect(first_one).to eq([items.first])
	end

	it 'treats legacy firstN mode shorthand as invalid' do
		items = [
			build_item({ 'title' => 'One', 'contributors' => %w[alice bob] }),
			build_item({ 'title' => 'Two', 'contributors' => %w[bob alice] })
		]

		filtered = apply_filters(
			items,
			{
				'contributors' => {
					'match' => 'alice',
					'mode' => 'first2',
					'split' => false
				}
			}
		)

		expect(filtered).to eq(items)
	end

	it 'supports per-filter split delimiters independent of global split' do
		items = [
			build_item({ 'title' => 'One', 'audience' => 'news|alerts' }),
			build_item({ 'title' => 'Two', 'audience' => 'news' })
		]

		filtered = apply_filters(
			items,
			{
				'audience' => {
					'match' => 'alerts',
					'split' => '|'
				}
			}
		)

		expect(filtered).to eq([items.first])
	end

	it 'supports configurable today keywords for range filters' do
		current_time = DateTime.now
		start_of_today = DateTime.new(current_time.year, current_time.month, current_time.day, 0, 0, 0, current_time.offset)
		items = [
			build_item({ 'title' => 'Two Days Ago', 'published_at' => (start_of_today - 2 + Rational(43_200, 86_400)).iso8601 }),
			build_item({ 'title' => 'Yesterday', 'published_at' => (start_of_today - 1 + Rational(43_200, 86_400)).iso8601 }),
			build_item({ 'title' => 'Today End', 'published_at' => (start_of_today + Rational(86_399, 86_400)).iso8601 }),
			build_item({ 'title' => 'Tomorrow', 'published_at' => (start_of_today + 1 + Rational(43_200, 86_400)).iso8601 })
		]

		filtered = apply_filters(
			items,
			{
				'published_at' => {
					'min' => 'daystart-1',
					'max' => 'daystart'
				}
			},
			today_keyword: 'daystart'
		)

		expect(filtered).to eq([items[1], items[2]])
	end

	it 'uses only renamed now and today keywords for range filters' do
		current_time = DateTime.now
		start_of_today = DateTime.new(current_time.year, current_time.month, current_time.day, 0, 0, 0, current_time.offset)
		items = [
			build_item({ 'title' => 'Today', 'published_at' => (start_of_today + Rational(43_200, 86_400)).iso8601 }),
			build_item({ 'title' => 'Future', 'published_at' => (current_time + 2).iso8601 })
		]

		aliased_today = apply_filters(items, { 'published_at' => { 'max' => 'daystart' } }, today_keyword: 'daystart')
		released_today = apply_filters(items, { 'published_at' => { 'max' => 'today' } }, today_keyword: 'daystart')
		aliased_now = apply_filters(items, { 'published_at' => { 'max' => 'currenttime + 86400' } }, now_keyword: 'currenttime')
		released_now = apply_filters(items, { 'published_at' => { 'max' => 'now + 86400' } }, now_keyword: 'currenttime')

		expect(aliased_today).to eq([items.first])
		expect(released_today).to eq(items)
		expect(aliased_now).to eq([items.first])
		expect(released_now).to eq(items)
	end

	it 'supports now keyword offsets in whole seconds' do
		current_time = DateTime.now
		items = [
			build_item({ 'title' => 'Past', 'published_at' => (current_time - Rational(7_200, 86_400)).iso8601 }),
			build_item({ 'title' => 'Current', 'published_at' => current_time.iso8601 }),
			build_item({ 'title' => 'Future', 'published_at' => (current_time + Rational(7_200, 86_400)).iso8601 })
		]

		filtered = apply_filters(
			items,
			{
				'published_at' => {
					'min' => 'now - 3600',
					'max' => 'now + 3600'
				}
			}
		)

		expect(filtered).to eq([items[1]])
	end

	it 'treats non-integer keyword offsets as invalid range filters' do
		current_time = DateTime.now
		items = [
			build_item({ 'title' => 'Current', 'published_at' => current_time.iso8601 }),
			build_item({ 'title' => 'Future', 'published_at' => (current_time + 1).iso8601 })
		]

		filtered_today = apply_filters(
			items,
			{
				'published_at' => {
					'min' => 'today - 0.5',
					'max' => 'today + 0.5'
				}
			}
		)

		filtered_now = apply_filters(
			items,
			{
				'published_at' => {
					'min' => 'now - 0.5',
					'max' => 'now + 0.5'
				}
			}
		)

		expect(filtered_today).to eq(items)
		expect(filtered_now).to eq(items)
	end

	it 'ignores invalid mixed-type range definitions gracefully' do
		items = [
			build_item({ 'title' => 'One', 'rating' => 1 }),
			build_item({ 'title' => 'Two', 'rating' => 2 })
		]

		filtered = apply_filters(
			items,
			{
				'rating' => {
					'min' => 1,
					'max' => '2026-01-01T00:00:00+00:00'
				}
			}
		)

		expect(filtered).to eq(items)
	end

	it 'supports inclusive and exclusive range mode boundaries' do
		items = [
			build_item({ 'title' => 'One', 'rating' => 1 }),
			build_item({ 'title' => 'Two', 'rating' => 2 }),
			build_item({ 'title' => 'Three', 'rating' => 3 })
		]

		min_exclusive = apply_filters(
			items,
			{
				'rating' => {
					'min' => 2,
					'max' => 3,
					'mode' => 'min-exclusive max-inclusive'
				}
			}
		)
		max_exclusive = apply_filters(
			items,
			{
				'rating' => {
					'min' => 1,
					'max' => 3,
					'mode' => 'min-inclusive max-exclusive'
				}
			}
		)

		expect(min_exclusive).to eq([items[2]])
		expect(max_exclusive).to eq([items[0], items[1]])
	end

	it 'treats invalid range mode definitions as invalid filters' do
		items = [
			build_item({ 'title' => 'One', 'rating' => 1 }),
			build_item({ 'title' => 'Two', 'rating' => 2 })
		]

		filtered = apply_filters(
			items,
			{
				'rating' => {
					'min' => 1,
					'max' => 2,
					'mode' => 'bad-mode'
				}
			}
		)

		expect(filtered).to eq(items)
	end

	it 'supports filtering by the synthetic collection key' do
		items = [
			build_item({ 'title' => 'Site Page' }),
			build_item({ 'title' => 'Product One' }, collection: 'products'),
			build_item({ 'title' => 'Guide One' }, collection: 'guides')
		]

		filtered = apply_filters(items, { 'collection' => 'products' })
		expect(filtered).to eq([items[1]])
	end

	it 'treats exists true and false as strict negations after value processing' do
		items = [
			build_item({ 'title' => 'Missing' }),
			build_item({ 'title' => 'Empty Array', 'links' => [] }),
			build_item({ 'title' => 'Blank String', 'links' => '' }),
			build_item({ 'title' => 'Whitespace String', 'links' => '   ' }),
			build_item({ 'title' => 'Present String', 'links' => 'project' }),
			build_item({ 'title' => 'Split Array', 'links' => 'one,two' })
		]

		exists_result = apply_filters(items, { 'links' => { 'exists' => true } })
		missing_result = apply_filters(items, { 'links' => { 'exists' => false } })

		expect(exists_result).to eq([items[4], items[5]])
		expect(missing_result).to eq([items[0], items[1], items[2], items[3]])
		expect(exists_result | missing_result).to match_array(items)
		expect(exists_result & missing_result).to eq([])
	end

	it 'treats blank strings as absent even when split is disabled' do
		items = [
			build_item({ 'title' => 'Blank', 'summary' => '   ' }),
			build_item({ 'title' => 'Present', 'summary' => ' hello ' })
		]

		exists_result = apply_filters(items, { 'summary' => { 'exists' => true, 'split' => false } })
		missing_result = apply_filters(items, { 'summary' => { 'exists' => false, 'split' => false } })

		expect(exists_result).to eq([items[1]])
		expect(missing_result).to eq([items[0]])
	end

	it 'supports exists type checks including datetime alias and forgiving booleans and numerics' do
		items = [
			build_item({ 'title' => 'Array', 'value' => 'one,two' }),
			build_item({ 'title' => 'String', 'value' => 'one' }),
			build_item({ 'title' => 'Boolean', 'value' => ' false ' }),
			build_item({ 'title' => 'Integer Like', 'value' => '1.0' }),
			build_item({ 'title' => 'Float Like', 'value' => '1.5' }),
			build_item({ 'title' => 'Date Like', 'value' => '2026-01-01' })
		]

		expect(apply_filters(items, { 'value' => { 'exists' => 'array' } })).to eq([items[0]])
		expect(apply_filters(items, { 'value' => { 'exists' => 'string' } })).to eq([items[1], items[2], items[3], items[4], items[5]])
		expect(apply_filters(items, { 'value' => { 'exists' => 'boolean', 'split' => false } })).to eq([items[2]])
		expect(apply_filters(items, { 'value' => { 'exists' => 'int', 'split' => false } })).to eq([items[3]])
		expect(apply_filters(items, { 'value' => { 'exists' => 'float', 'split' => false } })).to eq([items[3], items[4]])
		expect(apply_filters(items, { 'value' => { 'exists' => 'datetime', 'split' => false } })).to eq([items[5]])
	end

	it 'supports length-aware min and max when exists specifies array or string' do
		items = [
			build_item({ 'title' => 'Array Long', 'tags' => 'one,two,three', 'name' => 'Alpha' }),
			build_item({ 'title' => 'Array Short', 'tags' => 'one', 'name' => 'Go' }),
			build_item({ 'title' => 'String Long', 'tags' => 'solo', 'name' => 'Bravo' })
		]

		array_filtered = apply_filters(
			items,
			{
				'tags' => {
					'exists' => 'array',
					'min' => 2
				}
			}
		)
		string_filtered = apply_filters(
			items,
			{
				'name' => {
					'exists' => 'string',
					'min' => 4,
					'split' => false
				}
			}
		)

		expect(array_filtered).to eq([items[0]])
		expect(string_filtered).to eq([items[0], items[2]])
	end

	it 'combines exists, match, and range rules from one hash using shared mode tokens' do
		items = [
			build_item({ 'title' => 'Long Match', 'audience' => 'news,alerts' }),
			build_item({ 'title' => 'Short Match', 'audience' => 'alerts' }),
			build_item({ 'title' => 'Long Miss', 'audience' => 'news,updates' })
		]

		filtered = apply_filters(
			items,
			{
				'audience' => {
					'exists' => 'array',
					'match' => 'alerts',
					'min' => 1,
					'mode' => 'auto min-exclusive'
				}
			}
		)

		expect(filtered).to eq([items[0]])
	end

	it 'treats conflicting shared mode tokens as an invalid filter' do
		items = [
			build_item({ 'title' => 'One', 'tags' => %w[ruby jekyll] }),
			build_item({ 'title' => 'Two', 'tags' => ['ruby'] })
		]

		filtered = apply_filters(
			items,
			{
				'tags' => {
					'match' => 'ruby',
					'mode' => 'auto strict'
				}
			}
		)

		expect(filtered).to eq(items)
	end

	describe '.filter_to_s' do
		it 'renders scalar filters as readable expressions' do
			expect(described_class.filter_to_s('news')).to eq("match news (auto, split:',')")
		end

		it 'renders joined include groups and ranges' do
			expect(described_class.filter_to_s({ 'include' => %w[a b], 'join' => 'and' })).to eq(
				"match a (auto, split:',') and match b (auto, split:',')"
			)
			expect(described_class.filter_to_s({ 'min' => 2, 'max' => 5 })).to eq('2.0 to 5.0 (min-inclusive max-inclusive)')
		end

		it 'reports invalid filters without raising' do
			expect(described_class.filter_to_s({ 'bogus' => 1 })).to eq('[invalid filter]')
		end
	end
end
