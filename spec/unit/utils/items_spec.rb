# frozen_string_literal: true

ItemsSpecItem = Struct.new(:data)

RSpec.describe Jekyll::Plugins::PaginateV3::Utils do
	describe '.calculate_number_of_pages' do
		it 'returns the page count for fixed per-page values' do
			expect(described_class.calculate_number_of_pages(Array.new(7), 3)).to eq(3)
		end

		it 'returns one empty page for empty item sets' do
			expect(described_class.calculate_number_of_pages([], 3)).to eq(1)
		end

		it 'supports per-page patterns with the final entry reused' do
			expect(described_class.calculate_number_of_pages(Array.new(10), [2, 3])).to eq(4)
		end
	end

	describe '.pagination_template?' do
		it 'detects template and enabled pagination frontmatter' do
			expect(described_class.pagination_template?(ItemsSpecItem.new({ 'pagination' => { 'template' => true } }))).to be_truthy
			expect(described_class.pagination_template?(ItemsSpecItem.new({ 'pagination' => { 'enabled' => true } }))).to be_truthy
		end

		it 'rejects items without usable pagination frontmatter' do
			expect(described_class.pagination_template?(ItemsSpecItem.new({}))).to be_falsey
			expect(described_class.pagination_template?(ItemsSpecItem.new({ 'pagination' => {} }))).to be_falsey
			expect(described_class.pagination_template?(ItemsSpecItem.new(nil))).to be_falsey
			expect(described_class.pagination_template?(Object.new)).to be_falsey
		end
	end
end
