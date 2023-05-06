require 'cli/ui'
require 'faraday'
require 'nokogiri'
require 'open-uri'

class Crawler
  attr_accessor :url

  BASE_URL = 'https://annas-archive.org'.freeze
  SEARCH_QUERY = '/search?q='.freeze

  def initialize
    CLI::UI::StdoutRouter.enable
  end

  def start
    keywords = CLI::UI.ask('What book to download ?')
    search_keywords = gen_search_keywords(keywords)
    response = retrieve_html(search_keywords)
    book_links = retrieve_book_links(response.body)
    loop do
      selected_book_link, is_exit = display_books_selection(book_links)
      break if is_exit

      download_book(selected_book_link)
    end
  end

  def display_books_selection(book_links)
    selected_book_link = nil
    is_exit = false
    CLI::UI::Prompt.ask("There are #{book_links.length} books to download, choose one") do |handler|
      handler.option('Terminate the program') { |_selection| is_exit = true }
      book_links.each do |book_link|
        handler.option(book_link) { |selection| selected_book_link = selection }
      end
    end
    [selected_book_link, is_exit]
  end

  def gen_search_keywords(keywords)
    keywords.split(' ').join('+')
  end

  def gen_search_url(search_keywords)
    BASE_URL + SEARCH_QUERY + search_keywords
  end

  def gen_book_link(book_id)
    "#{BASE_URL}/md5/#{book_id}"
  end

  def retrieve_html(search_keywords)
    response = nil
    CLI::UI::Spinner.spin('Getting HTML content') do |_spinner|
      response = Faraday.get(gen_search_url(search_keywords))
    end
    response
  end

  def retrieve_book_links(html)
    raw_book_links = html.scan(%r{href="/md5/(.*)" })
    book_links = []
    raw_book_links.each do |book_link|
      book_links.push(gen_book_link(book_link[0]))
    end
    book_links
  end

  def download_book(url)
    response = nil
    CLI::UI::Spinner.spin('Getting Book Page') do |_spinner|
      response = Faraday.get(url)
    end
    title, book_img, download_link = retrieve_book_info(response.body)
    puts "Title: #{title}"
    puts "Book Cover: #{book_img}"
    CLI::UI::Prompt.ask('Do you want to download this book ?') do |handler|
      handler.option('yes') { |_selection| puts 'Processing to download the book' }
      handler.option('no') { |_selection| return nil }
    end
    CLI::UI::Spinner.spin('Downloading file') do |_spinner|
      save_book(title, download_link)
    end
  end

  def save_book(title, url)
    ext = url.split('.').last
    File.open("#{title}.#{ext}", 'wb') do |file|
      URI.open(url) do |pdf|
        file.write(pdf.read)
      end
    end
  end

  def retrieve_book_info(html)
    html_doc = Nokogiri::HTML(html)
    title = html_doc.xpath('//div[@class="text-3xl font-bold"]').text
    book_img = html_doc.xpath('//img[@class="float-right max-w-[25%] ml-4"]')[0]['src']
    download_link = html_doc.xpath('//a[@class="js-download-link"]')[2]['href']
    [title, book_img, download_link]
  end
end

crawler = Crawler.new
crawler.start
