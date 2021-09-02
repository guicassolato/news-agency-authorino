# frozen_string_literal: true

require 'net/http'
require 'json'

class Reader
  def initialize(endpoint:, access_token:, categories: [], wait_interval: 5)
    @endpoint = endpoint
    @access_token = access_token
    @categories = categories
    @wait_interval = wait_interval
    @past_news = []
    @shutdown = false
  end

  def call
    log "Watching categories: #{categories.join(', ')}"

    while active?
      categories.each(&method(:feed_news))
      wait
    end

    log 'Shutting down...'
  end

  def shutdown!
    @shutdown = true
  end

  def active?
    !@shutdown
  end

  protected

  SEPARATOR = ('-'*60).freeze

  attr_reader :endpoint, :access_token, :categories, :wait_interval

  def feed_news(category)
    uri = URI(endpoint)
    uri.path = "/#{category}"
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{access_token}" if access_token
      response = http.request(request)
      case response
      when Net::HTTPSuccess
        news = JSON.parse(response.body)
        news.each do |article|
          next if @past_news.include?(article['id'])
          puts [SEPARATOR, "Category: #{category.capitalize}", "Title: #{article['title']}", "Author: #{article['author']}", "Date: #{article['date']}", '', article['body']].join("\n")
          @past_news << article['id']
        end
      else
        log "failed to fetch news: #{response.code} #{response.message}"
      end
    end
  rescue Errno::ECONNREFUSED, Net::OpenTimeout => e
    log e.message
    nil
  end

  def wait
    sleep wait_interval
  end

  def log(message)
    puts "[#{Time.now}] #{message}"
  end
end

news_api_url = ENV['NEWS_API_URL'] or raise ArgumentError, 'missing news-api url'
access_token_file_path = ENV.fetch('ACCESS_TOKEN_PATH', '/var/run/secrets/tokens/reader-bot-token')
access_token = File.exists?(access_token_file_path) ? File.read(access_token_file_path).chomp : nil
categories = ENV['CATEGORIES'].to_s.split(',')
raise ArgumentError, 'missing at least one category to watch' if categories.empty?
wait_interval = ENV.fetch('WAIT_INTERVAL', 5).to_i

reader = Reader.new(endpoint: news_api_url, access_token: access_token, categories: categories, wait_interval: wait_interval)

Signal.trap('TERM') { reader.shutdown! }

reader.call
