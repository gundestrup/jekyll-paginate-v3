# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Templates::Builder do
	# Builds a report without touching site internals on error paths.
	def build_with(site_config)
		described_class.new(
			site: nil,
			site_config: site_config,
			add_item_lambda: proc {},
			resolve_items_lambda: proc {},
			log_lambda: proc {}
		).build
	end

	it 'returns an empty report when no generate definitions are configured' do
		expect(build_with({})).to eq('total' => 0, 'entries' => [])
		expect(build_with({ 'templates' => { 'generate' => 'oops' } })).to eq('total' => 0, 'entries' => [])
	end

	it 'marks invalid generate definitions without creating templates' do
		report = build_with({ 'templates' => { 'generate' => [nil, 'junk'] } })

		expect(report['total']).to eq(0)
		expect(report['entries'].map { |entry| entry['valid'] }).to eq([false, false])
	end

	it 'rejects generated template collections with more than two targets' do
		expect do
			build_with({ 'syntax' => { 'split' => ',' }, 'templates' => { 'generate' => [{ 'collection' => 'a,b,c' }] } })
		end.to raise_error(ArgumentError, /at most two values/)
	end
end
