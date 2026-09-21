# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Utils do
	describe '.normalise_layout_name' do
		it 'preserves nested layout paths while removing an optional extension' do
			expect(described_class.normalise_layout_name('html/product/listing.html')).to eq('html/product/listing')
			expect(described_class.normalise_layout_name('html/product/listing')).to eq('html/product/listing')
		end
	end

	describe '.replace_tokens' do
		it 'prefers the longest placeholder name when placeholders overlap' do
			output = described_class.replace_tokens(
				'/page:foobar:foo:bar',
				{
					'foo' => 'small',
					'foob' => 'large',
					'bar' => 'tail'
				}
			)

			expect(output).to eq('/pagelargearsmalltail')
		end

		it 'returns the original template when token map is not a hash' do
			output = described_class.replace_tokens('/page:foo', nil)
			expect(output).to eq('/page:foo')
		end
	end

	describe 'pagination placeholders' do
		it 'supports canonical syntax and replaces every occurrence' do
			expect(described_class.format_page_number('{{ num }}/{{ num }}/{{ max }}', 2, 7)).to eq('2/2/7')
		end

		it 'supports representation filters on title placeholders' do
			output = described_class.format_page_title(
				'{{ title | raw }} / {{ title | slugify }}',
				'Old Shoes',
				1,
				1
			)

			expect(output).to eq('Old Shoes / old-shoes')
		end

		it 'does not recursively resolve placeholder syntax introduced by a value' do
			expect(described_class.format_page_title('{{ title }} {{ num }}', ':num', 3, 3)).to eq(':num 3')
		end
	end

	describe '.comma_delimited_array' do
		it 'splits comma-delimited strings into trimmed entries' do
			expect(described_class.comma_delimited_array('a, b,, c ')).to eq(%w[a b c])
			expect(described_class.comma_delimited_array(['x', 'y,z'])).to eq(%w[x y z])
		end
	end

	describe '.merge_generated_template_pagination' do
		it 'lets generated config override layout defaults by default' do
			merged = described_class.merge_generated_template_pagination(
				{ 'per_page' => 5 },
				{ 'per_page' => 9, 'enabled' => true },
				nil
			)

			expect(merged['per_page']).to eq(5)
			expect(merged['enabled']).to eq(true)
		end

		it 'keeps legacy v2 override order and strips layout enabled' do
			merged = described_class.merge_generated_template_pagination(
				{ 'per_page' => 5 },
				{ 'per_page' => 9, 'enabled' => false },
				'v2'
			)

			expect(merged['per_page']).to eq(9)
			expect(merged).not_to have_key('enabled')
		end
	end
end
