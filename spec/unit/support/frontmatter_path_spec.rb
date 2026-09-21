# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Support::FrontmatterPath do
	describe '#traverse' do
		it 'reads values through a single array level' do
			path = described_class.new(arrays: :expand)
			data = { 'a' => [{ 'b' => 1 }, { 'b' => 2 }] }

			expect(path.traverse(data, 'a.b')).to eq([1, 2])
		end

		it 'expands deeper array nesting without consuming the segment' do
			path = described_class.new(arrays: :expand)
			data = { 'a' => [[{ 'b' => 1 }, { 'b' => 9 }], [{ 'b' => 2 }]] }

			expect(path.traverse(data, 'a.b')).to eq([{ 'b' => 1 }, { 'b' => 9 }, { 'b' => 2 }])
		end

		it 'keeps only the first entry of deeper arrays when array mode is first' do
			path = described_class.new(arrays: :first)
			data = { 'a' => [[{ 'b' => 1 }, { 'b' => 9 }], [{ 'b' => 2 }]] }

			expect(path.traverse(data, 'a.b')).to eq([{ 'b' => 1 }, { 'b' => 2 }])
		end
	end

	describe 'array mode validation' do
		it 'raises for unsupported array traversal modes' do
			expect do
				described_class.new(arrays: 'bogus')
			end.to raise_error(ArgumentError, /Unsupported array traversal mode/)
		end
	end
end
