# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Support::LooseScalar do
	it 'parses loose booleans from values and strings' do
		expect(described_class.boolean(true)).to eq(true)
		expect(described_class.boolean(false)).to eq(false)
		expect(described_class.boolean(' TRUE ')).to eq(true)
		expect(described_class.boolean('false')).to eq(false)
		expect(described_class.boolean('maybe')).to be_nil
	end

	it 'parses integer and float numbers from loose strings' do
		expect(described_class.number(3)).to eq(3)
		expect(described_class.number(1.5)).to eq(1.5)
		expect(described_class.number(' 4 ')).to eq(4)
		expect(described_class.number('1.25')).to eq(1.25)
		expect(described_class.number('cat')).to be_nil
	end

	it 'treats whole floats as integral numbers' do
		expect(described_class.integral_number?(1)).to eq(true)
		expect(described_class.integral_number?('1.0')).to eq(true)
		expect(described_class.integral_number?(1.5)).to eq(false)
	end

	it 'normalises native dates, times, and datetimes' do
		date = Date.new(2026, 1, 1)
		time = Time.utc(2026, 1, 1, 12, 30, 45)
		datetime = DateTime.new(2026, 1, 1, 12, 30, 45)

		expect(described_class.date(date)).to eq(date.to_datetime)
		expect(described_class.datetime(time)).to eq(time.to_datetime)
		expect(described_class.datetime(datetime)).to equal(datetime)
	end

	it 'recognises supported date separators when each separator repeats' do
		%w[2026-01-02 2026/01/02 2026.01.02 2026:01:02].each do |value|
			expect(described_class.datetime(value)).to eq(DateTime.new(2026, 1, 2))
		end
	end

	it 'recognises supported time separators, optional seconds, fractions, and matching timezones' do
		minute_precision = described_class.datetime('2026-01-02T03:04+01:30')
		hyphenated = described_class.datetime('2026/01/02 03-04-05.125 +01-30')
		hyphenated_without_seconds = described_class.datetime('2026-01-02T03-04-01-30')
		dotted = described_class.datetime("2026.01.02\t03.04.05 -01.30")

		expect(minute_precision.iso8601).to eq('2026-01-02T03:04:00+01:30')
		expect(hyphenated.iso8601(3)).to eq('2026-01-02T03:04:05.125+01:30')
		expect(hyphenated_without_seconds.iso8601).to eq('2026-01-02T03:04:00-01:30')
		expect(dotted.iso8601).to eq('2026-01-02T03:04:05-01:30')
		expect(described_class.datetime('2026:01:02 03:04:05Z').iso8601).to eq('2026-01-02T03:04:05+00:00')
	end

	it 'rejects incomplete, inconsistent, and non-date strings' do
		[
			'not a date',
			'September 29',
			'12:30:45',
			'2026-01',
			'2026-1-01',
			'2026-01/01',
			'2026-02-30',
			'2026-01-01T25:00',
			'2026-01-01T12:30+25:00',
			'2026-01-01T12/30',
			'2026-01-01T12:30-45',
			'2026-01-01T12.30.45 +01:00',
			'2026-01-01T12:30.123',
			'2026-01-01t12:30:45z',
			'LYwqSnWuTw29cB9eizhgrQ',
			'HOFkLzQgQhu1cDMBcgn29g',
			'abc2026-01-01',
			'2026-01-01abc'
		].each do |value|
			expect(described_class.datetime(value)).to be_nil, "expected #{value.inspect} to be rejected"
		end
	end

	it 'normalises generic comparable values without inferring dates from strings' do
		expect(described_class.comparable(' 4 ')).to eq(4)
		expect(described_class.comparable('1.25')).to eq(1.25)
		expect(described_class.comparable('2026-01-01')).to eq('2026-01-01')
		expect(described_class.comparable(' hello ')).to eq('hello')
		expect(described_class.comparable('2026-01-01', must_cast: true)).to be_nil
		expect(described_class.comparable(Object.new, must_cast: true)).to be_nil
	end

	it 'keeps opaque identifiers as distinct comparable strings' do
		small_format_print_id = 'LYwqSnWuTw29cB9eizhgrQ'
		website_id = 'HOFkLzQgQhu1cDMBcgn29g'

		expect(described_class.comparable(small_format_print_id)).to eq(small_format_print_id)
		expect(described_class.comparable(website_id)).to eq(website_id)
		expect(described_class.comparable(small_format_print_id)).not_to eq(described_class.comparable(website_id))
	end

	it 'treats integers and floats as comparable values' do
		expect(described_class.comparable_values?(1, 1.0)).to eq(true)
		expect(described_class.comparable_values?(DateTime.parse('2026-01-01'), Date.parse('2026-01-01').to_datetime)).to eq(true)
		expect(described_class.comparable_values?(1, 'cat')).to eq(false)
	end
end
