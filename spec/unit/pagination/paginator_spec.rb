# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Pagination::Paginator do
	it 'raises an error when current page exceeds total pages' do
		expect do
			described_class.new(
				per_page: 10,
				items: [1, 2, 3],
				current_page: 3,
				total_pages: 2,
				item_keyword: 'items'
			)
		end.to raise_error(ArgumentError, /cannot be greater than total pages/)
	end

	it 'exposes v3 neighbour objects and trail entries from bound page objects' do
		page_one = Struct.new(:url, :data).new('/articles/', { 'title' => 'Articles' })
		page_two = Struct.new(:url, :data).new('/articles/page/2/', { 'title' => 'Articles - page 2' })
		page_three = Struct.new(:url, :data).new('/articles/page/3/', { 'title' => 'Articles - page 3' })

		paginator = described_class.new(
			per_page: 2,
			items: [1, 2, 3, 4, 5],
			current_page: 2,
			total_pages: 3,
			item_keyword: 'posts',
			compatibility: nil
		)
		paginator.bind_pages(
			current_page_object: page_two,
			previous_page_object: page_one,
			next_page_object: page_three,
			first_page_object: page_one,
			last_page_object: page_three
		)
		paginator.trail = [
			paginator.build_trail_reference(page_number: 1, page_object: page_one, current: false, distance: -1),
			paginator.build_trail_reference(page_number: 2, page_object: nil, current: true, distance: 0),
			paginator.build_trail_reference(page_number: 3, page_object: page_three, current: false, distance: 1)
		]
		payload = paginator.to_h

		expect(payload['posts']).to eq([3, 4])
		expect(payload).not_to have_key('items')
		expect(payload).not_to have_key('total_items')
		expect(payload['total_indexes']).to eq(3)
		expect(payload['current'].num).to eq(2)
		expect(payload['current'].page).to be_nil
		expect(payload['current'].count).to eq(2)
		expect(payload['current'].start).to eq(3)
		expect(payload['current'].to_h['end']).to eq(4)
		expect(payload['previous'].num).to eq(1)
		expect(payload['prev'].num).to eq(1)
		expect(payload['prev']).to equal(payload['previous'])
		expect(payload['prev'].page.url).to eq('/articles/')
		expect(payload['prev'].count).to eq(2)
		expect(payload['prev'].start).to eq(1)
		expect(payload['prev'].to_h['end']).to eq(2)
		expect(payload['next'].num).to eq(3)
		expect(payload['next'].page.url).to eq('/articles/page/3/')
		expect(payload['next'].count).to eq(1)
		expect(payload['next'].start).to eq(5)
		expect(payload['next'].to_h['end']).to eq(5)
		expect(payload['first'].page.url).to eq('/articles/')
		expect(payload['last'].page.url).to eq('/articles/page/3/')
		expect(payload['trail'].map(&:num)).to eq([1, 2, 3])
		expect(payload['trail'].map(&:distance)).to eq([-1, 0, 1])
		expect(payload['posts']).to eq([3, 4])
		expect(payload['total_posts']).to eq(5)
		expect(payload).not_to have_key('next_page_path')
	end

	it 'adds legacy v1/v2 keys when compatibility mode is enabled' do
		page_one = Struct.new(:url, :data).new('/articles/', { 'title' => 'Articles' })
		page_two = Struct.new(:url, :data).new('/articles/page/2/', { 'title' => 'Articles - page 2' })
		page_three = Struct.new(:url, :data).new('/articles/page/3/', { 'title' => 'Articles - page 3' })

		paginator = described_class.new(
			per_page: 2,
			items: [1, 2, 3, 4, 5],
			current_page: 2,
			total_pages: 3,
			item_keyword: 'posts',
			compatibility: 'v2'
		)
		paginator.bind_pages(
			current_page_object: page_two,
			previous_page_object: page_one,
			next_page_object: page_three,
			first_page_object: page_one,
			last_page_object: page_three
		)
		paginator.trail = [
			paginator.build_trail_reference(page_number: 1, page_object: page_one, current: false, distance: -1),
			paginator.build_trail_reference(page_number: 2, page_object: nil, current: true, distance: 0),
			paginator.build_trail_reference(page_number: 3, page_object: page_three, current: false, distance: 1)
		]
		payload = paginator.to_h

		expect(payload['page']).to eq(2)
		expect(payload['total_pages']).to eq(3)
		expect(payload['page_path']).to eq('/articles/page/2/')
		expect(payload['previous_page_path']).to eq('/articles/')
		expect(payload['next_page_path']).to eq('/articles/page/3/')
		expect(payload['first_page_path']).to eq('/articles/')
		expect(payload['last_page_path']).to eq('/articles/page/3/')
		expect(payload['page_trail']).to eq(
			[
				{ 'num' => 1, 'path' => '/articles/', 'title' => 'Articles' },
				{ 'num' => 2, 'path' => '/articles/page/2/', 'title' => 'Articles - page 2' },
				{ 'num' => 3, 'path' => '/articles/page/3/', 'title' => 'Articles - page 3' }
			]
		)
	end

	it 'falls back to items when the configured alias keyword is blank' do
		paginator = described_class.new(
			per_page: 5,
			items: [1],
			current_page: 1,
			total_pages: 1,
			item_keyword: '   ',
			compatibility: nil
		)
		payload = paginator.to_h

		expect(payload['items']).to eq([1])
		expect(payload['total_items']).to eq(1)
	end

	it 'supports variable per-page windows and compatibility per_page projection' do
		page_one = Struct.new(:url, :data).new('/articles/', { 'title' => 'Articles' })
		page_three = Struct.new(:url, :data).new('/articles/page/3/', { 'title' => 'Articles - page 3' })
		page_four = Struct.new(:url, :data).new('/articles/page/4/', { 'title' => 'Articles - page 4' })
		page_five = Struct.new(:url, :data).new('/articles/page/5/', { 'title' => 'Articles - page 5' })

		page_windows = Jekyll::Plugins::PaginateV3::Utils.build_pagination_windows(10, [3, 1, 2])
		paginator = described_class.new(
			per_page: [3, 1, 2],
			items: (1..10).to_a,
			current_page: 4,
			total_pages: 5,
			item_keyword: 'items',
			compatibility: 'v2',
			page_windows: page_windows
		)
		paginator.bind_pages(
			current_page_object: page_four,
			previous_page_object: page_three,
			next_page_object: page_five,
			first_page_object: page_one,
			last_page_object: page_five
		)
		payload = paginator.to_h

		expect(payload['items']).to eq([7, 8])
		expect(payload['current'].count).to eq(2)
		expect(payload['current'].start).to eq(7)
		expect(payload['current'].to_h['end']).to eq(8)
		expect(payload['previous'].count).to eq(2)
		expect(payload['prev'].count).to eq(2)
		expect(payload['prev']).to equal(payload['previous'])
		expect(payload['prev'].start).to eq(5)
		expect(payload['prev'].to_h['end']).to eq(6)
		expect(payload['next'].count).to eq(2)
		expect(payload['next'].start).to eq(9)
		expect(payload['next'].to_h['end']).to eq(10)
		expect(payload['first'].count).to eq(3)
		expect(payload['first'].start).to eq(1)
		expect(payload['first'].to_h['end']).to eq(3)
		expect(payload['per_page']).to eq(2)
		expect(payload['page']).to eq(4)
		expect(payload['next_page_path']).to eq('/articles/page/5/')
	end

	it 'exposes grouped-set navigation payload through canonical groups and group shortcut' do
		current_group_page = Struct.new(:url, :data).new('/topics/100/', { 'title' => '100' })
		next_group_page = Struct.new(:url, :data).new('/topics/80/', { 'title' => '80' })

		paginator = described_class.new(
			per_page: 10,
			items: [1, 2, 3],
			current_page: 1,
			total_pages: 1,
			item_keyword: 'items'
		)

		current_reference = described_class::GroupReference.new(
			num: 1,
			page_object: nil,
			item_count: 1,
			range_start: '80',
			range_end: '100'
		)
		next_reference = described_class::GroupReference.new(
			num: 2,
			page_object: next_group_page,
			item_count: 1,
			range_start: '60',
			range_end: '80'
		)
		first_reference = described_class::GroupReference.new(
			num: 1,
			page_object: current_group_page,
			item_count: 1,
			range_start: '80',
			range_end: '100'
		)

		top_level_payload = described_class::GroupPayload.new(
			key: 'category',
			current: current_reference,
			next_reference: nil,
			first_reference: first_reference,
			last_reference: first_reference,
			previous_reference: nil
		)
		deepest_level_payload = described_class::GroupPayload.new(
			key: 'size',
			current: current_reference,
			next_reference: next_reference,
			prev_reference: nil,
			first_reference: first_reference,
			last_reference: next_reference
		)
		paginator.groups = [top_level_payload, deepest_level_payload]

		payload = paginator.to_h
		expect(payload['groups'].length).to eq(2)
		expect(payload['groups'].last.key).to eq('size')
		expect(payload['group']).not_to be_nil
		expect(payload['group'].key).to eq('size')
		expect(payload['group'].current.num).to eq(1)
		expect(payload['group'].current.to_h).to include('start' => '80', 'end' => '100')
		expect(payload['group'].next.page.url).to eq('/topics/80/')
		expect(payload['group'].previous).to be_nil
		expect(payload['group'].prev).to equal(payload['group'].previous)
	end
end
