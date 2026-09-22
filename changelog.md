# Changelog


## 0.2.1.alpha

* Fixed a serious bug in date parsing, which too eagerly coerced strings to dates. Strings are now only read as dates in explicitly date-aware operations, and only if the string is in ISO 6801 shape.


## 0.2.0.alpha

* Placeholder pipeline overhauled and made more robust.
  * Format updated to `{{ placeholder }}`.
  * Can exert some control over whether the placeholder will be slugified or not.
  * Original `:placeholder` format still supported.
* **Breaking change**: `slugify` modes refined, and dangerous modes retired.
* Page 1 now remains the exact original object when under `self` mode.
* Indexes now include `pagination.base` (the URL fragment of the originating template) and `pagination.path`.
* **Breaking change**: permalinks must be relative to the pagination template and cannot begin with `/`. Root-relative `paginate_path` remains supported only in V1 compatibility mode.


## 0.1.0.alpha.3

* Synthetic filenames are now more meaningful, to aid with debugging.
* Bugfix: keyword changes now work.


## 0.1.0.alpha.2

* Ensure collection document order is preserved when operating on templates in collections.


## 0.1.0.alpha.1

* Fix and refactor to ensure pagination *templates* can themselves be *items* that are paginated over. Index pages (generated from templates) remain excluded from pagination.


## 0.1.0.alpha

* Templates can be pages or documents, and are found at `pagination.templates.location`.
* Pagination can look for `items` in pages or collections with optional globs.
* Generic frontmatter filters (`match`, `include`/`exclude`, `min`/`max`, regex, join modes).
* Generate templates from config at `pagination.templates.generate` or with `group` config for multi-level/bunched grouping by numeric, date or alphabetic values.
* Multi-level `sort` options.
* Nested-key access (default `.`), equivalent keys (for example `tag`/`tags`), and delimiter-driven array parsing.
* New structured format for `page.paginator` (with v2 compatibility mode).
* Paginate between index sets with `paginator.group`.
* Explicit compatibility modes (`compatibility: v1` / `v2`) to interpret legacy configuration.


## V2 1.9.4

Historical record of key features from the prior gem.

* Primary config lived under `pagination` in `_config.yml` (`enabled`, `collection`, `per_page`, `permalink`, `title`, `limit`, `offset`, `sort_field`, `sort_reverse`, `trail`, `indexpage`, `extension`), with page-level frontmatter overrides.
* Paginated `posts` by default, but could paginate a named collection, multiple collections, or special `all`.
* Added first-class filtering by `category`, `tag`, and `locale`; comma-delimited values acted as combined filters.
* Supported advanced sorting, including nested fields via `:` path syntax (for example `author:name:first`).
* Extended paginator payload beyond v1 with `page_path`, `first_page(_path)`, `last_page(_path)`, and `page_trail` (while keeping v1-style fields).
* Marked generated pagination pages with `page.autogen = "jekyll-paginate-v2"` for detection in templates.
* Included optional, experimental `autopages` to generate tag/category/collection index pages from site content.
* Included legacy compatibility mode for old `paginate`/`paginate_path` config (mutually exclusive with new `pagination` mode).


## V1 1.1.0

Historical record of key features from the prior gem.

* Enabled only when `site.config['paginate']` was set; read configuration from `paginate` (per-page size) and `paginate_path`.
* Paginated only `site.site_payload['site']['posts']`, always excluding posts with `hidden: true`.
* Selected exactly one template page: `index.html` within the source-to-`paginate_path` hierarchy (preferring the deepest matching path).
* Used the template page as page 1 and cloned it for page 2+ (`site.pages << newpage`), with `newpage.dir` set from `paginate_path`.
* Required `paginate_path` to contain `:num` for numbered pages; raised `ArgumentError` otherwise.
* Exposed minimal paginator/liquid contract: `page`, `per_page`, `posts`, `total_posts`, `total_pages`, `previous_page(_path)`, `next_page(_path)`.
* Computed page counts by ceiling division and raised on invalid page requests (`page > total_pages`).
