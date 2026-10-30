# frozen_string_literal: true

RSpec.describe 'Pagination integration: rendered HTML output' do
	it 'renders paginator items, position, and navigation into the built files' do
		files = jekyll_merge(
			post_files(5),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Home',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 2,
									'sort' => 'title asc'
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |_site, output_files|
			page_one = output_files.read('index.html')
			expect(page_one).to include('<p id="current-page">1</p>')
			expect(page_one).to include('<p id="total-pages">3</p>')
			expect(page_one).to include('<li>Post 01</li>', '<li>Post 02</li>')
			expect(page_one).not_to include('<li>Post 03</li>')

			page_two_path = %w[2.html 2/index.html].find { |relative_path| output_file?(output_files, relative_path) }
			expect(page_two_path).not_to be_nil
			page_two = output_files.read(page_two_path)
			expect(page_two).to include('<p id="current-page">2</p>')
			expect(page_two).to include('<li>Post 03</li>', '<li>Post 04</li>')

			page_three_path = %w[3.html 3/index.html].find { |relative_path| output_file?(output_files, relative_path) }
			expect(page_three_path).not_to be_nil
			page_three = output_files.read(page_three_path)
			expect(page_three).to include('<p id="current-page">3</p>')
			expect(page_three).to include('<li>Post 05</li>')
		end
	end

	it 'renders the paginator trail with resolved page urls' do
		files = jekyll_merge(
			post_files(9),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Home',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 3,
									'sort' => 'title asc',
									'trail' => { 'before' => 1, 'after' => 1 }
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |_site, output_files|
			page_two_path = %w[2.html 2/index.html].find { |relative_path| output_file?(output_files, relative_path) }
			expect(page_two_path).not_to be_nil
			page_two = output_files.read(page_two_path)
			trail_entries = page_two.scan(%r{<li>(\d+)\|([^|]*)\|([^|]*)\|([^|]*)</li>}).flatten

			expect(page_two).to include('<ol id="trail">')
			expect(trail_entries).to include('2', 'true')
			expect(page_two).to match(%r{<li>1\|/\|})
		end
	end

	it 'renders grouped index pages with their group membership' do
		files = jekyll_merge(
			post_files(4) do |index|
				{ 'category' => (index <= 2 ? 'news' : 'updates') }
			end,
			jekyll_files do
				folder 'categories' do
					file 'index.md' do
						frontmatter(
							pagination_template_frontmatter(
								{
									'title' => 'Categories',
									'permalink' => '/categories/:category/',
									'pagination' => {
										'enabled' => true,
										'items' => 'posts',
										'group' => 'category',
										'per_page' => 10,
										'sort' => 'title asc'
									}
								}
							)
						)
						contents('Category listing')
					end
				end
			end
		)

		jekyll_build(default_site, files: files) do |_site, output_files|
			news_page = output_files.read('categories/news/index.html')
			expect(news_page).to include('<li>Post 01</li>', '<li>Post 02</li>')
			expect(news_page).not_to include('<li>Post 03</li>')

			updates_page = output_files.read('categories/updates/index.html')
			expect(updates_page).to include('<li>Post 03</li>', '<li>Post 04</li>')
			expect(updates_page).not_to include('<li>Post 01</li>')
		end
	end
end
