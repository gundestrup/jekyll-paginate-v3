# frozen_string_literal: true

# These defaults suit conventional gems. Set only the values that differ.
GEMSPEC_FILE = nil
GEM_REQUIRE_PATH = nil
PACKAGE_DIRECTORY = 'pkg'
VERIFICATION_CACHE_DIRECTORY = File.join(PACKAGE_DIRECTORY, '.verification-gems')
CHANGELOG_FILE = 'changelog.md'
RELEASE_TAG_PREFIX = 'v'
RUBYGEMS_HOST = 'https://rubygems.org'

require 'digest'
require 'fileutils'
require 'net/http'
require 'rspec/core/rake_task'
require 'rubygems/package'
require 'uri'

# Finds the sole gemspec unless its filename is configured explicitly.
def gemspec_file
	return GEMSPEC_FILE if GEMSPEC_FILE

	gemspec_files = Dir['*.gemspec']
	return gemspec_files.first if gemspec_files.length == 1

	raise "Expected one gemspec in the project root, found #{gemspec_files.length}; set GEMSPEC_FILE explicitly"
end

# Runs a command outside Bundler against an isolated gem home, failing the build when the command is unsuccessful.
def run_isolated_gem_command!(gem_home, *command)
	environment = ENV.each_key.each_with_object({}) do |name, clean_environment|
		clean_environment[name] = nil if name.start_with?('BUNDLE_') || name.start_with?('BUNDLER_')
	end
	environment.merge!({
		'GEM_HOME' => gem_home,
		'GEM_PATH' => gem_home,
		'RUBYLIB' => nil,
		'RUBYOPT' => nil,
		'RUBYGEMS_GEMDEPS' => nil
	})

	return if system(environment, *command)

	raise "Command failed: #{command.join(' ')}"
end

# Builds the gem with RubyGems and moves the resulting package into the configured directory.
def build_package!(specification, package_directory:)
	FileUtils.mkdir_p(package_directory)
	generated_gem_file = Gem::Package.build(specification)
	gem_file = File.join(package_directory, File.basename(generated_gem_file))
	FileUtils.mv(generated_gem_file, gem_file)
	gem_file
end

# Confirms that the built gem describes the requested release and contains exactly the files selected by the gemspec.
def inspect_package!(gem_file, specification)
	package = Gem::Package.new(gem_file)
	package.verify
	built_specification = package.spec
	package_files = package.contents.reject { |file| file.end_with?('/') }.sort
	expected_files = specification.files.sort

	raise 'Built gem identity does not match the gemspec' unless built_specification.name == specification.name && built_specification.version == specification.version
	raise 'Built gem contents do not match the gemspec' unless package_files == expected_files

	puts "Inspected #{built_specification.full_name}:"
	package_files.each { |file| puts "  #{file}" }
	puts 'Package contents match the gemspec.'
end

# Returns a reusable gem home specific to the active Ruby and runtime dependency requirements.
def verification_gem_home(specification, cache_directory:)
	runtime_dependencies = specification.runtime_dependencies.sort_by(&:name).map do |dependency|
		"#{dependency.name}:#{dependency.requirement}"
	end
	dependency_fingerprint = Digest::SHA256.hexdigest(runtime_dependencies.join("\n"))[0, 12]
	ruby_engine = defined?(RUBY_ENGINE) ? RUBY_ENGINE : 'ruby'
	ruby_identity = "#{ruby_engine}-#{RUBY_VERSION}-#{Gem::Platform.local}"

	File.join(cache_directory, ruby_identity, dependency_fingerprint)
end

# Installs the package into a cached isolated gem home, then loads its public entry point.
def verify_installed_package!(gem_file, specification, require_path:, cache_directory:)
	gem_home = verification_gem_home(specification, cache_directory: cache_directory)
	FileUtils.mkdir_p(gem_home)
	run_isolated_gem_command!(gem_home, Gem.ruby, '-S', 'gem', 'install', '--no-document', '--install-dir', gem_home, gem_file)

	verification = "gem #{specification.name.inspect}, '= #{specification.version}'; require #{require_path.inspect}; loaded_specification = Gem.loaded_specs.fetch(#{specification.name.inspect}); abort 'Version verification failed' unless loaded_specification.version == Gem::Version.new(#{specification.version.to_s.inspect})"
	run_isolated_gem_command!(gem_home, Gem.ruby, '-e', verification)

	puts 'Installed package public entry point verified.'
end

# Checks RubyGems for the exact name, version and platform, and fails safely when availability cannot be determined.
def gem_version_published?(specification, host:)
	name = URI.encode_www_form_component(specification.name)
	version = URI.encode_www_form_component(specification.version.to_s)
	endpoint = URI("#{host}/api/v2/rubygems/#{name}/versions/#{version}.json")
	endpoint.query = URI.encode_www_form(platform: specification.platform.to_s)
	response = Net::HTTP.get_response(endpoint)

	return true if response.is_a?(Net::HTTPSuccess)
	return false if response.is_a?(Net::HTTPNotFound)

	raise "Unable to check whether #{specification.full_name} is published: RubyGems returned #{response.code} #{response.message}"
end

# Extracts the release notes beneath an exact level-two version heading, stopping at the next level-two heading.
def changelog_entry_for(version, changelog_file:)
	changelog = File.read(changelog_file, encoding: 'UTF-8')
	heading = /^##[ \t]+#{Regexp.escape(version.to_s)}[ \t]*\r?$/
	heading_match = changelog.match(heading)

	raise "#{changelog_file} does not contain a level-two heading for #{version}" unless heading_match

	next_heading = changelog.match(/^##[ \t]+.+\r?$/, heading_match.end(0))
	entry = changelog[heading_match.end(0)...(next_heading ? next_heading.begin(0) : changelog.length)].strip

	raise "The changelog entry for #{version} does not contain any release notes" if entry.empty?

	entry
end

# Ensures the release has been tagged locally before it can be published.
def require_release_tag!(version, prefix:)
	tag = "#{prefix}#{version}"
	return tag if system('git', 'show-ref', '--verify', '--quiet', "refs/tags/#{tag}", out: File::NULL, err: File::NULL)

	raise "Required git tag #{tag} does not exist"
end

specification = Gem::Specification.load(gemspec_file)
raise "Unable to load #{gemspec_file}" unless specification

require_path = GEM_REQUIRE_PATH || specification.name

desc 'Lint Markdown documentation'
task :markdownlint do
	sh 'npx --yes markdownlint-cli2@0.23.2'
end

desc 'Run the test suite'
RSpec::Core::RakeTask.new(:test)

desc 'Test, build and verify the gem'
task :build do
	generated_gem_file = specification.file_name
	gem_file = File.join(PACKAGE_DIRECTORY, specification.file_name)

	# Remove previous output so a failed build cannot leave a stale release candidate behind.
	FileUtils.rm_f(generated_gem_file)
	FileUtils.rm_f(gem_file)

	begin
		Rake::Task[:test].invoke
		gem_file = build_package!(specification, package_directory: PACKAGE_DIRECTORY)
		inspect_package!(gem_file, specification)
		verify_installed_package!(gem_file, specification, require_path: require_path, cache_directory: VERIFICATION_CACHE_DIRECTORY)
	rescue StandardError
		FileUtils.rm_f(gem_file)
		raise
	ensure
		FileUtils.rm_f(generated_gem_file)
	end
end

desc 'Publish the current gem version if it has been built and is not already published'
task :publish do
	gem_file = File.join(PACKAGE_DIRECTORY, specification.file_name)

	unless File.file?(gem_file)
		puts "Skipping publish: #{gem_file} does not exist."
		next
	end

	if gem_version_published?(specification, host: RUBYGEMS_HOST)
		puts "Skipping publish: #{specification.full_name} is already published."
		next
	end

	tag = require_release_tag!(specification.version, prefix: RELEASE_TAG_PREFIX)
	changelog_entry = changelog_entry_for(specification.version, changelog_file: CHANGELOG_FILE)

	puts
	puts "Changelog entry for #{tag}:"
	puts
	puts changelog_entry
	puts
	print "Publish #{specification.full_name} to RubyGems? (y/N) "
	$stdout.flush

	unless $stdin.gets.to_s.strip.casecmp('y').zero?
		puts 'Publish cancelled.'
		next
	end

	# Invoke RubyGems directly so authentication and multi-factor prompts behave as they do for gem push.
	next if system(Gem.ruby, '-S', 'gem', 'push', gem_file, '--host', RUBYGEMS_HOST)

	raise "Unable to publish #{specification.full_name}"
end
