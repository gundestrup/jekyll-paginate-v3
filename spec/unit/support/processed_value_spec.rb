# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Support::ProcessedValue do
	def build_value(raw_value, split: true, delimiter: ',')
		described_class.build(
			raw_value,
			string_array: Jekyll::Plugins::PaginateV3::Support::StringArray.new(delimiter: delimiter),
			split: split
		)
	end

	it 'keeps a single split token as a scalar string and many tokens as an array' do
		expect(build_value('news').value).to eq('news')
		expect(build_value('news,alerts').value).to eq(%w[news alerts])
	end

	it 'treats blank strings and empty arrays as absent' do
		expect(build_value('').present?).to eq(false)
		expect(build_value('   ', split: false).present?).to eq(false)
		expect(build_value([]).present?).to eq(false)
	end

	it 'splits array entries and discards blank members' do
		processed = build_value(['news,alerts', ' ', 'blog'])

		expect(processed.value).to eq(%w[news alerts blog])
		expect(processed.scalar_candidates).to eq(%w[news alerts blog])
	end

	it 'reports shape types and lengths from the prepared value' do
		expect(build_value('news').type?('string')).to eq(true)
		expect(build_value('news,alerts').type?('array')).to eq(true)
		expect(build_value('news').length).to eq(4)
		expect(build_value('news,alerts').length).to eq(2)
	end

	it 'supports forgiving scalar type checks and the datetime alias' do
		expect(build_value('false', split: false).type?('boolean')).to eq(true)
		expect(build_value('1.0', split: false).type?('int')).to eq(true)
		expect(build_value('1', split: false).type?('float')).to eq(true)
		expect(build_value('2026-01-01', split: false).type?('date')).to eq(true)
		expect(build_value('2026-01-01', split: false).type?('datetime')).to eq(true)
		expect(build_value('2026/01/01 12-30 +01-00', split: false).type?('datetime')).to eq(true)
		expect(build_value(Date.new(2026, 1, 1), split: false).type?('date')).to eq(true)
		expect(build_value(Time.utc(2026, 1, 1), split: false).type?('datetime')).to eq(true)
		expect(build_value(DateTime.new(2026, 1, 1), split: false).type?('date')).to eq(true)
		expect(build_value('September 29', split: false).type?('date')).to eq(false)
		expect(build_value('2026-01/01', split: false).type?('date')).to eq(false)
		expect(build_value('LYwqSnWuTw29cB9eizhgrQ', split: false).type?('datetime')).to eq(false)
	end

	it 'does not treat arrays as scalar typed values' do
		expect(build_value('1,2').type?('float')).to eq(false)
		expect(build_value(['true', 'false']).type?('boolean')).to eq(false)
	end
end
