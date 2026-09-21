# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Pagination::IndexReference do
	it 'exposes end via liquid_method_missing because end is a Ruby keyword' do
		reference = described_class.new(
			num: 1,
			page_object: nil,
			item_count: 2,
			start_item_index: 1,
			end_item_index: 4
		)

		expect(reference.liquid_method_missing('end')).to eq(4)
	end
end

RSpec.describe Jekyll::Plugins::PaginateV3::Pagination::TrailReference do
	it 'serialises trail metadata including current and distance' do
		reference = described_class.new(
			num: 2,
			page_object: nil,
			item_count: 4,
			start_item_index: 4,
			end_item_index: 7,
			current: true,
			distance: 0
		)

		expect(reference.to_h).to eq(
			'num' => 2,
			'page' => nil,
			'count' => 4,
			'start' => 4,
			'end' => 7,
			'current' => true,
			'distance' => 0
		)
	end
end

RSpec.describe Jekyll::Plugins::PaginateV3::Pagination::GroupReference do
	it 'exposes the range end via liquid_method_missing and to_h' do
		reference = described_class.new(
			num: 1,
			page_object: nil,
			item_count: 3,
			range_start: 'a',
			range_end: 'c'
		)

		expect(reference.liquid_method_missing('end')).to eq('c')
		expect(reference.to_h['end']).to eq('c')
	end

	it 'omits end when the group range is open' do
		reference = described_class.new(
			num: 1,
			page_object: nil,
			item_count: 3,
			range_start: 'a',
			range_end: nil
		)

		expect(reference.to_h).not_to have_key('end')
	end
end
