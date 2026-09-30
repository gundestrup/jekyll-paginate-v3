# frozen_string_literal: true

RSpec.describe 'Pagination integration: navigation, URLs, and trails' do
	it 'supports custom page2 permalink and title formatting' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				folder 'news' do
					file 'index.md' do
						frontmatter(
							pagination_template_frontmatter(
								{
									'title' => 'News',
									'permalink' => '/articles/',
									'pagination' => {
										'enabled' => true,
										'items' => 'posts',
										'sort' => 'title asc',
										'per_page' => 1,
										'permalink' => 'slice/:num/feed.json',
										'title' => ':title [page :num/:max]'
									}
								}
							)
						)
						contents('Template content')
					end
				end
			end
		)

		jekyll_build(default_site, files: files) do |site, output_files|
			page_one = page_by_url(site, '/articles/')
			page_two = page_by_url(site, '/articles/slice/2/feed.json')

			expect(page_one).not_to be_nil
			expect(page_two).not_to be_nil

			expect(output_file?(output_files, 'articles/index.html')).to be(true)
			expect(output_file?(output_files, 'articles/slice/2/feed.json')).to be(true)
			expect(page_one.data.fetch('title')).to eq('News')
			expect(page_two.data.fetch('title')).to eq('News [page 2/2]')
			expect(paginator_reference_url(page_one, 'next')).to eq('/articles/slice/2/feed.json')
			expect(paginator_reference_url(page_two, 'prev')).to eq('/articles/')
		end
	end

	it 'calculates previous/next/first/last paginator references consistently' do
		files = jekyll_merge(
			post_files(3),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 1
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			page_one = page_by_url(site, '/')
			page_two = page_by_url(site, '/2/')
			page_three = page_by_url(site, '/3/')

			expect(paginator_reference_number(page_one, 'prev')).to be_nil
			expect(normalise_url_for_match(paginator_reference_url(page_one, 'next'))).to eq('/2')
			expect(normalise_url_for_match(paginator_reference_url(page_two, 'previous'))).to eq('/')
			expect(normalise_url_for_match(paginator_reference_url(page_two, 'prev'))).to eq('/')
			expect(normalise_url_for_match(paginator_reference_url(page_two, 'next'))).to eq('/3')
			expect(paginator_reference_number(page_three, 'next')).to be_nil
			expect(normalise_url_for_match(paginator_reference_url(page_three, 'first'))).to eq('/')
			expect(normalise_url_for_match(paginator_reference_url(page_three, 'last'))).to eq('/3')
		end
	end

	it 'assigns a padded page trail window near boundaries' do
		files = jekyll_merge(
			post_files(4),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 1,
									'trail' => {
										'before' => 1,
										'after' => 1
									}
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			page_one = page_by_url(site, '/')
			page_two = page_by_url(site, '/2/')
			page_four = page_by_url(site, '/4/')

			expect(paginator_trail_numbers(page_one)).to eq([1, 2, 3])
			expect(paginator_trail_numbers(page_two)).to eq([1, 2, 3])
			expect(paginator_trail_numbers(page_four)).to eq([2, 3, 4])
		end
	end

	it 'renders chained paginator drop references in liquid templates' do
		files = jekyll_merge(
			post_files(10),
			jekyll_files do
				folder '_layouts' do
					file 'drop_probe.html' do
						contents(<<~HTML)
							<!doctype html>
							<html>
								<body>
									<p id="current-count">{{ paginator.current.count }}</p>
									<p id="current-start">{{ paginator.current.start }}</p>
									<p id="current-end">{{ paginator.current.end }}</p>
									<p id="previous-url">{% if paginator.previous and paginator.previous.page %}{{ paginator.previous.page.url }}{% endif %}</p>
									<p id="prev-url">{% if paginator.prev and paginator.prev.page %}{{ paginator.prev.page.url }}{% endif %}</p>
									<p id="next-url">{% if paginator.next and paginator.next.page %}{{ paginator.next.page.url }}{% endif %}</p>
									<p id="first-url">{% if paginator.first and paginator.first.page %}{{ paginator.first.page.url }}{% endif %}</p>
									<p id="last-url">{% if paginator.last and paginator.last.page %}{{ paginator.last.page.url }}{% endif %}</p>
									<ol id="trail-url-list">
										{% for entry in paginator.trail %}
											<li>{{ entry.num }}:{% if entry.page %}{{ entry.page.url }}{% else %}CURRENT{% endif %}</li>
										{% endfor %}
									</ol>
								</body>
							</html>
						HTML
					end
				end

				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'layout' => 'drop_probe',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => [3, 1, 2]
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site, output_files|
			page_two = page_by_url(site, '/2/')
			expect(page_two).not_to be_nil

			page_two_output = %w[2.html 2/index.html].find { |relative_path| output_file?(output_files, relative_path) }
			expect(page_two_output).not_to be_nil

			rendered = output_files.read(page_two_output)
			current_count = rendered[%r{<p id="current-count">(.*?)</p>}m, 1]
			current_start = rendered[%r{<p id="current-start">(.*?)</p>}m, 1]
			current_end = rendered[%r{<p id="current-end">(.*?)</p>}m, 1]
			previous_url = rendered[%r{<p id="previous-url">(.*?)</p>}m, 1]
			prev_url = rendered[%r{<p id="prev-url">(.*?)</p>}m, 1]
			next_url = rendered[%r{<p id="next-url">(.*?)</p>}m, 1]
			first_url = rendered[%r{<p id="first-url">(.*?)</p>}m, 1]
			last_url = rendered[%r{<p id="last-url">(.*?)</p>}m, 1]
			# nosemgrep: ruby-redos-string-scan — input is generator-produced HTML, not attacker data
			trail_lines = rendered.scan(%r{<li>(.*?)</li>}m).flatten.map do |entry|
				number, value = entry.split(':', 2)
				next "#{number}:CURRENT" if value == 'CURRENT'

				"#{number}:#{normalise_url_for_match(value)}"
			end

			expect(current_count).to eq('1')
			expect(current_start).to eq('4')
			expect(current_end).to eq('4')
			expect(normalise_url_for_match(previous_url)).to eq('/')
			expect(normalise_url_for_match(prev_url)).to eq('/')
			expect(normalise_url_for_match(next_url)).to eq('/3')
			expect(normalise_url_for_match(first_url)).to eq('/')
			expect(normalise_url_for_match(last_url)).to eq('/5')
			expect(trail_lines).to eq(
				[
					'1:/',
					'2:CURRENT',
					'3:/3',
					'4:/4',
					'5:/5'
				]
			)
		end
	end

	it 'rejects unsafe fully resolved pagination permalinks' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				file 'unsafe-permalink.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'permalink' => '/articles/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 1,
									'permalink' => 'page/{{ num }}#fragment'
								}
							}
						)
					)
					contents('Unsafe permalink template')
				end
			end
		)

		expect do
			jekyll_build(default_site, files: files) do |_site,|
			end
		end.to raise_error(JekyllTestHarness::SiteBuildError, /Invalid resolved permalink.*fragment marker/)
	end

	it 'rejects root-relative native V3 pagination permalinks' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				file 'articles.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'permalink' => '/articles/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 1,
									'permalink' => '/page/{{ num }}'
								}
							}
						)
					)
					contents('Articles')
				end
			end
		)

		expect do
			jekyll_build(default_site, files: files) do |_site,|
			end
		end.to raise_error(JekyllTestHarness::SiteBuildError, /native V3 pagination permalinks must be relative/)
	end
end
