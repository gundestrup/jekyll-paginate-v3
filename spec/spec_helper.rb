# frozen_string_literal: true

# SimpleCov must load before the library under test. The Cobertura
# formatter is CI-only — loading it unconditionally replaces the local
# HTML formatter. The coverage floor is gated on CI/COVERAGE so a focused
# local run of one spec file doesn't trip the suite-wide minimum.
require 'simplecov'
require 'simplecov-cobertura' if ENV['CI']

SimpleCov.start do
	enable_coverage :branch
	add_filter '/spec/'
	# Floor sits just under the measured baseline (93.7% line / 73.1%
	# branch on 2026-09-21) — raise it as coverage improves.
	minimum_coverage line: 93, branch: 73 if ENV['CI'] || ENV['COVERAGE']
	formatter SimpleCov::Formatter::CoberturaFormatter if ENV['CI']
end

require 'rspec'
require 'jekyll_test_harness'
require 'jekyll-paginate-v3'

require_relative 'support/integration_helpers'

# Install the Jekyll integration harness so each example can build a real site.
JekyllTestHarness.install!(framework: :rspec)

RSpec.configure do |config|
	config.disable_monkey_patching!
	config.order = :random
	config.include IntegrationHelpers

	Kernel.srand config.seed
end
