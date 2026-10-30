# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'pathname'

# True end-to-end coverage: drives the real `jekyll build` CLI in a
# subprocess against a fixture site on disk, then compares every rendered
# file byte-for-byte against committed golden output.
RSpec.describe 'jekyll build CLI' do
	repo_root = File.expand_path('../..', __dir__)
	fixture_site = File.join(repo_root, 'spec/fixtures/golden_site')
	golden_expected = File.join(repo_root, 'spec/fixtures/golden_expected')

	def build_site(source, destination)
		Open3.capture3(
			'bundle', 'exec', 'jekyll', 'build',
			'--source', source,
			'--destination', destination,
			'--quiet'
		)
	end

	it 'builds the fixture site successfully through the real CLI' do
		Dir.mktmpdir do |dir|
			source = File.join(dir, 'src')
			destination = File.join(dir, 'out')
			FileUtils.cp_r(fixture_site, source)

			_stdout, stderr, status = build_site(source, destination)

			expect(status).to be_success, "jekyll build failed:\n#{stderr}"
			expect(File.file?(File.join(destination, 'index.html'))).to be(true)
		end
	end

	it 'renders pagination output matching the golden files' do
		Dir.mktmpdir do |dir|
			source = File.join(dir, 'src')
			destination = File.join(dir, 'out')
			FileUtils.cp_r(fixture_site, source)

			_stdout, stderr, status = build_site(source, destination)
			expect(status).to be_success, "jekyll build failed:\n#{stderr}"

			expected_root = Pathname.new(golden_expected)
			expected_files = Dir[expected_root.join('**', '*').to_s].select { |path| File.file?(path) }
			expect(expected_files).not_to be_empty

			expected_files.each do |expected_path|
				relative = Pathname.new(expected_path).relative_path_from(expected_root).to_s
				actual_path = File.join(destination, relative)

				expect(File.file?(actual_path)).to be(true), "missing rendered output: #{relative}"
				expect(File.read(actual_path)).to eq(File.read(expected_path)), "rendered output diverged: #{relative}"
			end
		end
	end

	it 'fails the build when the site config is invalid' do
		Dir.mktmpdir do |dir|
			source = File.join(dir, 'src')
			destination = File.join(dir, 'out')
			FileUtils.cp_r(fixture_site, source)
			File.write(File.join(source, '_config.yml'), "title: Broken\npagination: [unclosed\n")

			_stdout, _stderr, status = build_site(source, destination)

			expect(status).not_to be_success
		end
	end
end
