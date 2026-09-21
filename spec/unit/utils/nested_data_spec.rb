# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Utils do
	describe '.fetch_nested_values' do
		it 'reads nested values through arrays of hashes' do
			data = {
				'product' => {
					'variants' => [
						{ 'name' => 'Small', 'size' => 34 },
						{ 'name' => 'Large', 'size' => 40 }
					]
				}
			}

			values = described_class.fetch_nested_values(data, 'product.variants.size', '.', {})
			expect(values).to eq([34, 40])
		end

		it 'applies equivalent keys only on matching full nested paths' do
			data = {
				'product' => {
					'tags' => ['ruby']
				},
				'tags' => ['jekyll']
			}
			equivalents = described_class.build_equivalent_lookup(
				[
					%w[tag tags],
					['product.tag', 'product.tags']
				]
			)

			product_values = described_class.fetch_nested_values(data, 'product.tag', '.', equivalents)
			root_values = described_class.fetch_nested_values(data, 'tag', '.', equivalents)

			expect(product_values).to eq(['ruby'])
			expect(root_values).to eq(['jekyll'])
		end
	end

	describe '.split_nested_key' do
		it 'splits paths on the configured separator' do
			expect(described_class.split_nested_key('a.b.c', '.')).to eq(%w[a b c])
			expect(described_class.split_nested_key('a:b:c', ':')).to eq(%w[a b c])
		end
	end

	describe '.resolve_hash_key' do
		it 'resolves exact string and symbol keys' do
			expect(described_class.resolve_hash_key({ 'tag' => 1 }, 'tag', {})).to eq('tag')
			expect(described_class.resolve_hash_key({ tag: 1 }, 'tag', {})).to eq(:tag)
			expect(described_class.resolve_hash_key({ 'other' => 1 }, 'tag', {})).to be_nil
		end

		it 'resolves equivalent key groups by full path' do
			lookup = described_class.build_equivalent_lookup([%w[tag tags]])
			expect(described_class.resolve_hash_key({ 'tags' => 1 }, 'tag', lookup)).to eq('tags')
		end
	end

	describe '.read_hash' do
		it 'reads string and symbol keys' do
			expect(described_class.read_hash({ 'a' => 1 }, 'a')).to eq(1)
			expect(described_class.read_hash({ a: 2 }, 'a')).to eq(2)
		end
	end
end
