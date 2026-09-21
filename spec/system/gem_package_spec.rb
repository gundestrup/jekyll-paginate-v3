# frozen_string_literal: true

RSpec.describe 'gem packaging' do
	let(:gemspec_path) { File.expand_path('../../jekyll-paginate-v3.gemspec', __dir__) }
	let(:gemspec) { Gem::Specification.load(gemspec_path) }

	it 'loads the gemspec and matches the library version' do
		expect(gemspec).not_to be_nil
		expect(gemspec.name).to eq('jekyll-paginate-v3')
		expect(gemspec.version.to_s).to eq(Jekyll::Plugins::PaginateV3::VERSION)
	end

	it 'ships only files that exist in the repository' do
		expect(gemspec.files).not_to be_empty

		gemspec.files.each do |file|
			expect(File.exist?(File.expand_path("../../#{file}", __dir__))).to be(true), "gemspec references missing file: #{file}"
		end
	end

	it 'declares consumer-facing metadata' do
		expect(gemspec.required_ruby_version).not_to be_nil
		expect(gemspec.homepage).to match(%r{\Ahttps://})
		expect(gemspec.licenses).not_to be_empty
		expect(gemspec.summary).not_to be_empty
	end

	it 'does not ship development artefacts' do
		expect(gemspec.files.grep(%r{\A(spec|coverage|pkg|\.github)/})).to be_empty
	end
end
