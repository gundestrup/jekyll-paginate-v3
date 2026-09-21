# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Core pagination orchestration model.
#
# Responsibilities:
# - discover pagination templates
# - generate configured templates (`pagination.templates.generate`)
# - resolve and filter/sort items per template
# - emit paginated index pages/documents
#
# Used by Generators::PaginationGenerator as the main runtime
# coordinator for the pagination pipeline.
class Model

	def initialize(site:, site_config:, log_lambda:, scoped_log_lambda_builder:, add_item_lambda:, remove_item_lambda:)
		@site = site
		@site_config = site_config
		@log_lambda = log_lambda
		@active_log_lambda = log_lambda
		@scoped_log_lambda_builder = scoped_log_lambda_builder
		@add_item_lambda = add_item_lambda
		@remove_item_lambda = remove_item_lambda
		@nested_separator = site_config.dig('syntax', 'separator')
		@split_delimiter = site_config.dig('syntax', 'split')
		@equivalents = site_config['equivalents']
		@item_keyword = site_config.dig('keywords', 'items') || Config::KEYWORD_DEFAULTS.fetch('items')
		@generated_index_sets = {}
		@clone_collection_cache = {}
		@template_search_reports = []
		@template_search_report_lookup = {}.compare_by_identity
		@template_search_duration_seconds = 0.0
		@item_resolution_pages = nil
		@item_resolution_documents_by_collection = nil
	end

	# Runs the full pagination pipeline for the current site build.
	def run
		log("Pagination pipeline start: compatibility=#{@site_config['compatibility'] || 'none'} templates.location=#{@site_config.dig('templates', 'location')} generate.count=#{@site_config.dig('templates', 'generate')&.length || 0}", 'debug')

		generated_template_report = build_generated_templates
		generated_template_count = generated_template_report['total'].to_i
		log("Generated #{generated_template_count} template(s).", 'debug')
		capture_item_resolution_sources!

		search_started_at = monotonic_seconds
		templates = discover_templates
		@template_search_duration_seconds = monotonic_seconds - search_started_at
		if templates.empty?
			log('Enabled, but no pagination templates were discovered.', 'warn')
			return build_run_report(processed_templates: 0, generated_template_report: generated_template_report)
		end

		log("Discovered #{templates.length} pagination template(s).", 'debug')
		enabled_templates = []
		disabled_templates = 0
		templates.each do |template|
			next unless template.data['pagination'].is_a?(Hash)

			template_pagination_source = Utils.safe_hash(template.data['pagination'])
			template_pagination = merged_template_pagination_config(template, template_pagination_source)
			template_config = Config::Normaliser.normalise_template_config(@site_config, template_pagination)
			template_log_lambda = scoped_log_lambda(template_config['debug'])
			unless template_config['enabled']
				disabled_templates += 1
				with_log_lambda(template_log_lambda) do
					log("Skipping template '#{Utils.relative_item_path(template)}' because merged `pagination.enabled` is false.", 'debug')
				end
				next
			end
			enabled_templates << [template, template_config, template_pagination_source, template_log_lambda]
		end

		if enabled_templates.empty?
			log('Discovered pagination templates, but all resolved to `pagination.enabled: false` after config merge.', 'warn')
			return build_run_report(processed_templates: 0, generated_template_report: generated_template_report)
		end

		processed = 0
		enabled_templates.each do |template, template_config, template_pagination_source, template_log_lambda|
			with_log_lambda(template_log_lambda) do
				log("Paginating template '#{Utils.relative_item_path(template)}' with items=#{template_config['items']} filters=#{template_config['filters']}.", 'debug')
				begin
					template_pagination_report = paginate_template(template, template_config, template_pagination_source)
					record_template_search_report_totals(template, template_pagination_report)
				rescue StandardError => error
					log("Template '#{Utils.relative_item_path(template)}' failed: #{error.class}: #{error.message}", 'error')
					raise
				end
			end
			processed += 1
		end

		apply_grouped_set_navigation!
		log("Skipped #{disabled_templates} discovered template(s) because merged `pagination.enabled` is false.", 'debug') if disabled_templates.positive?

		log("Pagination pipeline complete: processed #{processed} template(s).", 'debug')
		build_run_report(processed_templates: processed, generated_template_report: generated_template_report)
	end

	private

	# Writes one message through the currently active pagination logger.
	def log(message, level = 'info')
		@active_log_lambda.call(message, level)
	end

	# Runs one block with a temporary logger callback, restoring the
	# previous logger afterwards.
	def with_log_lambda(log_lambda)
		previous_log_lambda = @active_log_lambda
		@active_log_lambda = log_lambda || @log_lambda
		yield
	ensure
		@active_log_lambda = previous_log_lambda
	end

	# Builds a logger callback that can override debug output for one
	# template while leaving info/warn/error handling shared.
	def scoped_log_lambda(debug_enabled)
		return @log_lambda if @scoped_log_lambda_builder.nil?

		@scoped_log_lambda_builder.call(debug_enabled: debug_enabled)
	end

	# Builds the public run report consumed by the generator logger.
	def build_run_report(processed_templates:, generated_template_report:)
		{
			'processed_templates' => processed_templates,
			'generated_template_report' => generated_template_report,
			'search_location_report' => @template_search_reports,
			'search_duration_seconds' => @template_search_duration_seconds
		}
	end

	# Builds synthetic pagination templates from `templates.generate`.
	def build_generated_templates
		builder = Templates::Builder.new(
			site: @site,
			site_config: @site_config,
			add_item_lambda: @add_item_lambda,
			resolve_items_lambda: method(:resolve_items),
			log_lambda: @active_log_lambda
		)
		report = builder.build
		return report if report.is_a?(Hash)

		{
			'total' => report.to_i,
			'entries' => []
		}
	end

	# Captures the source items used by later `items` searches so
	# pagination item resolution remains stable even after templates are
	# removed and replaced by generated index pages.
	#
	# This frozen snapshot is the invariant that stops emitted pagination
	# pages from feeding back into later item searches.
	def capture_item_resolution_sources!
		@item_resolution_pages = @site.pages.dup
		@item_resolution_documents_by_collection = {}

		@site.collections.each do |label, collection|
			@item_resolution_documents_by_collection[label] = collection.docs.dup
		end

		log(
			"Captured item-resolution sources: pages=#{@item_resolution_pages.length} collections=#{@item_resolution_documents_by_collection.length} documents=#{all_collection_documents.length}.",
			'debug'
		)
	end

	# Keeps the captured item-resolution view immutable when a source
	# template itself is retained and mutated into pagination page one.
	# Later templates should still see the source template metadata rather
	# than the emitted index metadata attached to the retained object.
	def replace_item_resolution_source!(source_item, source_snapshot)
		@item_resolution_pages&.map! do |item|
			item.equal?(source_item) ? source_snapshot : item
		end

		@item_resolution_documents_by_collection&.each_value do |documents|
			documents.map! do |item|
				item.equal?(source_item) ? source_snapshot : item
			end
		end
	end

	# Discovers all pages/documents configured as pagination templates.
	def discover_templates
		search_entries = Query::Parser.parse(@site_config.dig('templates', 'location'), @site_config['keywords'], split_delimiter: @split_delimiter)
		# Report site pages before collection sources regardless of configuration order.
		page_search_entries, collection_search_entries = search_entries.partition { |entry| entry['type'] == Query::Parser::SEARCH_TYPE_PAGES }
		search_entries = page_search_entries + collection_search_entries
		reset_template_search_reporting_state

		combined_candidates = []
		search_entries.each_with_index do |entry, entry_index|
			entry_candidates = resolve_entry(entry)
			combined_candidates.concat(entry_candidates)

			entry_templates = entry_candidates.select { |item| template_discovery_state(item) == 'enabled' }.uniq
			report_entry = {
				'entry_number' => entry_index + 1,
				'label' => format_search_entry_label(entry),
				'templates_found' => entry_templates.length,
				'paginated_items' => 0,
				'indexes' => 0
			}
			@template_search_reports << report_entry
			entry_candidates.uniq.each do |candidate|
				(@template_search_report_lookup[candidate] ||= []) << report_entry
			end
		end

		candidates = combined_candidates.uniq
		candidates.sort_by! { |item| Utils.relative_item_path(item) }
		discovery_counts = Hash.new(0)
		templates = candidates.select do |item|
			state = template_discovery_state(item)
			discovery_counts[state] += 1
			state == 'enabled'
		end

		log(
			"Template discovery summary: candidates=#{candidates.length} enabled=#{discovery_counts['enabled']} disabled=#{discovery_counts['disabled']} missing_pagination=#{discovery_counts['missing_pagination']} invalid_data=#{discovery_counts['invalid_data']}.",
			'debug'
		)

		generated_templates = (@site.pages + all_collection_documents).select do |item|
			next false unless item.respond_to?(:data)
			next false unless item.data.is_a?(Hash)
			next false unless item.data.dig('paginate_v3', 'generated_template')

			template_discovery_state(item) == 'enabled'
		end
		log("Template discovery: added #{generated_templates.length} generated template(s) outside configured search location.", 'debug') if generated_templates.any?

		templates.concat(generated_templates)
		templates.uniq!
		apply_implicit_v1_template_fallback(candidates, templates)
	end

	# Resets search-location reporting state before template discovery.
	def reset_template_search_reporting_state
		@template_search_reports = []
		@template_search_report_lookup = {}.compare_by_identity
	end

	# Formats one parsed search entry for info-level summary output.
	def format_search_entry_label(entry)
		Query::Parser.entry_label(entry)
	end

	# Adds paginated item/index totals to all matching search entry reports.
	def record_template_search_report_totals(template, template_pagination_report)
		report_entries = @template_search_report_lookup[template]
		return if report_entries.nil? || report_entries.empty?

		report_entries.each do |report_entry|
			report_entry['paginated_items'] += template_pagination_report['paginated_items'].to_i
			report_entry['indexes'] += template_pagination_report['indexes'].to_i
		end
	end

	# Returns a monotonic timestamp suitable for elapsed-duration
	# measurements that should not be affected by wall-clock changes.
	def monotonic_seconds
		Process.clock_gettime(Process::CLOCK_MONOTONIC)
	end

	# Merges pagination settings from the template and its layout hierarchy.
	#
	# Default precedence:
	# - layout provides defaults
	# - template overrides layout
	#
	# v2 compatibility precedence:
	# - template provides defaults
	# - layout overrides template
	def merged_template_pagination_config(template, template_pagination_source = nil)
		template_pagination = Utils.safe_hash(template_pagination_source.nil? ? template.data['pagination'] : template_pagination_source)
		return template_pagination if template_pagination.empty?

		layout_pagination = layout_pagination_config(template)
		return template_pagination if layout_pagination.empty?

		if template_compatibility_mode(template_pagination) == 'v2'
			Jekyll::Utils.deep_merge_hashes(template_pagination, layout_pagination)
		else
			Jekyll::Utils.deep_merge_hashes(layout_pagination, template_pagination)
		end
	end

	# Resolves merged pagination settings from the template layout chain.
	#
	# Parent layouts are merged first so nearer layouts override them.
	def layout_pagination_config(template)
		layout_name = template_layout_name(template)
		return {} if layout_name.empty?

		layout_chain = []
		seen_layouts = {}
		current_layout_name = layout_name

		until current_layout_name.empty? || seen_layouts[current_layout_name]
			seen_layouts[current_layout_name] = true
			layout = find_layout(current_layout_name)
			break if layout.nil?

			layout_chain << layout
			current_layout_name = Utils.safe_hash(layout.data)['layout'].to_s.strip
		end

		merged_layout_pagination = {}
		layout_chain.reverse_each do |layout|
			merged_layout_pagination = Jekyll::Utils.deep_merge_hashes(
				merged_layout_pagination,
				Utils.safe_hash(Utils.safe_hash(layout.data)['pagination'])
			)
		end

		merged_layout_pagination
	end

	# Resolves one template layout name from frontmatter.
	def template_layout_name(template)
		Utils.safe_hash(template.data)['layout'].to_s.strip
	end

	# Resolves a layout object by key, accepting optional file extensions.
	def find_layout(layout_name)
		layout = @site.layouts[layout_name]
		return layout unless layout.nil?

		normalised_layout_name = Utils.normalise_layout_name(layout_name)
		return nil if normalised_layout_name == layout_name

		@site.layouts[normalised_layout_name]
	end

	# Resolves template compatibility mode from local and site config.
	def template_compatibility_mode(template_pagination)
		mode = template_pagination['compatibility']
		mode = @site_config['compatibility'] if mode.nil?
		value = mode.to_s.strip.downcase
		return value if %w[v1 v2].include?(value)

		nil
	end

	# Ensures enabled templates have the minimum required pagination keys.
	def validate_required_template_config!(template, template_config)
		return if configured_value_present?(template_config['items'])

		raise ArgumentError, "Template '#{Utils.relative_item_path(template)}' is enabled for pagination but does not define `pagination.items` (directly, via layout pagination config, or via global pagination template defaults)."
	end

	# Returns true when a template config value is explicitly configured.
	def configured_value_present?(value)
		return false if value.nil?
		return false if value.is_a?(String) && value.strip.empty?
		return false if value.is_a?(Array) && value.empty?
		return false if value.is_a?(Hash) && value.empty?

		true
	end

	# Categorises a template candidate and marks enabled templates.
	def template_discovery_state(item)
		return 'invalid_data' unless item.respond_to?(:data)
		return 'invalid_data' unless item.data.is_a?(Hash)

		pagination = Utils.safe_hash(item.data['pagination'])
		return 'missing_pagination' if pagination.empty?
		return 'disabled' unless pagination['enabled']

		item.data['pagination'] = pagination
		item.data['pagination']['template'] = true
		'enabled'
	end

	# Provides an implicit v1 migration path when old `paginate` config
	# is present but no page has `pagination.enabled: true`.
	#
	# This keeps v1 compatibility focused on config migration while still
	# allowing the shared v3 pipeline to process the intended template.
	def apply_implicit_v1_template_fallback(candidates, templates)
		return templates unless templates.empty?
		return templates unless @site_config['compatibility'] == 'v1'
		return templates unless legacy_v1_site_config_present?

		template = legacy_v1_template_candidate(candidates)
		if template.nil?
			log("v1 compatibility: no implicit template candidate matched paginate path '#{@site_config['permalink']}'.", 'warn')
			return templates
		end

		template.data['pagination'] = Utils.safe_hash(template.data['pagination'])
		template.data['pagination']['enabled'] = true
		template.data['pagination']['template'] = true

		log("v1 compatibility: no explicit templates found; selected implicit template '#{Utils.relative_item_path(template)}'.", 'debug')
		[template]
	end

	# Detects whether the site includes the legacy v1 top-level config key.
	def legacy_v1_site_config_present?
		!@site.config['paginate'].nil?
	end

	# Selects the legacy v1 index page candidate as an implicit template.
	# The deepest matching `index.html` under the configured paginate path
	# hierarchy is preferred.
	def legacy_v1_template_candidate(items)
		source_root = File.expand_path(@site.config['source'].to_s)
		paginate_path = @site_config['permalink']

		items.select { |item| legacy_v1_pagination_candidate?(source_root, paginate_path, item) }.sort_by { |item| -item.path.to_s.size }.first
	end

	# Mirrors v1 template candidate detection rules for migration fallback.
	def legacy_v1_pagination_candidate?(source_root, paginate_path, item)
		return false unless item.respond_to?(:name)
		return false unless item.respond_to?(:path)
		return false if item.is_a?(Jekyll::Document)
		return false if Utils.generated_index?(item)
		return false unless item.name.to_s == 'index.html'

		page_dir = File.dirname(File.expand_path(Utils.remove_leading_slash(item.path), source_root))
		full_paginate_path = File.expand_path(Utils.remove_leading_slash(paginate_path), source_root)
		legacy_v1_in_hierarchy?(source_root, page_dir, File.dirname(full_paginate_path))
	end

	# Traverses parent directories to determine whether the page directory
	# is inside the legacy paginate path hierarchy.
	def legacy_v1_in_hierarchy?(source_root, page_dir, paginate_dir)
		source_parent = File.dirname(File.expand_path(source_root))
		current_dir = paginate_dir

		loop do
			return false if current_dir == File.dirname(current_dir)
			return false if current_dir == source_parent
			return true if page_dir == current_dir

			current_dir = File.dirname(current_dir)
		end
	end

	# Resolves the shared search format into concrete site items and then
	# applies generic inclusion/exclusion flags.
	#
	# `exclude_items` is used by the pagination pipeline to remove the
	# active source template from its own item set while leaving other
	# pagination templates eligible for ordinary item searches.
	#
	# Emitted pagination indexes are kept out by the frozen source items
	# captured earlier in the pipeline, rather than by ad hoc filtering.
	def resolve_items(raw_search, include_hidden: false, exclude_items: nil)
		entries = Query::Parser.parse(raw_search, @site_config['keywords'], split_delimiter: @split_delimiter)
		if entries.empty?
			log("Resolving items from search=#{raw_search.inspect} produced no parsed entries.", 'debug')
			return []
		end

		excluded_item_keys = excluded_item_identity_keys(exclude_items)
		log("Resolving items from search=#{raw_search.inspect} (entries=#{entries.length}, include_hidden=#{include_hidden}, exclude_items=#{excluded_item_keys.length}).", 'debug')
		resolved = []
		entries.each do |entry|
			resolved.concat(resolve_entry(entry))
		end

		resolved.uniq!
		resolved.sort_by! { |item| Utils.relative_item_path(item) }
		log("Resolved #{resolved.length} unique item(s) before exclusion filters.", 'debug')
		log_item_path_sample('Resolved item sample before exclusions', resolved)

		excluded_hidden = include_hidden ? 0 : resolved.count { |item| item['hidden'] }
		excluded_explicit_items = excluded_item_keys.empty? ? 0 : resolved.count { |item| excluded_item_keys.include?(item_identity_key(item)) }

		resolved.select! { |item| !item['hidden'] } unless include_hidden
		resolved.select! { |item| !excluded_item_keys.include?(item_identity_key(item)) } unless excluded_item_keys.empty?

		if excluded_hidden.positive? || excluded_explicit_items.positive?
			log("Excluded hidden=#{excluded_hidden} explicit=#{excluded_explicit_items} from resolved items.", 'debug')
		end
		log("Resolved #{resolved.length} item(s) after exclusion filters.", 'debug')
		log_item_path_sample('Resolved item sample after exclusions', resolved)
		resolved
	end

	# Builds stable identity keys for explicit item exclusions.
	#
	# The key uses collection label plus relative path so cloned template
	# objects still match their source item when we need to exclude self.
	def excluded_item_identity_keys(items)
		Utils.arrayify(items).map { |item| item_identity_key(item) }.uniq
	end

	# Returns one stable item identity key for item-resolution exclusions.
	def item_identity_key(item)
		[Utils.item_collection_label(item).to_s, Utils.relative_item_path(item)]
	end

	# Resolves one parsed search entry (a private source type or collection label).
	def resolve_entry(entry)
		type = entry['type']
		paths = entry['paths']
		source_items = source_items_for_entry_type(type)
		if source_items.nil?
			log("Search entry type='#{type}' did not match a configured search keyword or known collection; resolved 0 items.", 'warn')
			return []
		end

		log("Resolving entry type='#{type}' paths=#{paths.inspect} from #{source_items.length} source item(s).", 'debug')
		matched_items = source_items.select do |item|
			Query::Parser.path_allowed?(Utils.relative_item_path(item), paths)
		end
		log("Entry type='#{type}' matched #{matched_items.length}/#{source_items.length} item(s) after path filtering.", 'debug')
		log_item_path_sample("Entry type='#{type}' matched item sample", matched_items)
		matched_items
	end

	# Resolves source items for one parsed search entry type.
	def source_items_for_entry_type(type)
		case type
		when Query::Parser::SEARCH_TYPE_PAGES
			@item_resolution_pages || @site.pages
		when Query::Parser::SEARCH_TYPE_ALL
			all_collection_documents
		when Query::Parser::SEARCH_TYPE_EVERYTHING
			(@item_resolution_pages || @site.pages) + all_collection_documents
		else
			return @item_resolution_documents_by_collection[type] if @item_resolution_documents_by_collection&.key?(type)

			collection = @site.collections[type]
			return nil if collection.nil?

			collection.docs
		end
	end

	# Logs a compact sample of item paths for debug diagnostics.
	def log_item_path_sample(label, items, limit: 5)
		return if items.empty?

		maximum = [limit.to_i, 1].max
		sample_paths = items.first(maximum).map { |item| Utils.relative_item_path(item) }
		extra_count = items.length - sample_paths.length
		extra_suffix = extra_count.positive? ? " (+#{extra_count} more)" : ''
		log("#{label}: #{sample_paths.join(', ')}#{extra_suffix}.", 'debug')
	end

	# Purpose: Implements all collection documents for this component.
	# Connects to: the surrounding pagination flow in this file.
	# Params: none.
	# Returns: a value consumed by the next pipeline step.
	def all_collection_documents
		return @item_resolution_documents_by_collection.values.flatten if @item_resolution_documents_by_collection

		@site.collections.values.flat_map(&:docs)
	end
end

end
end
end
end
