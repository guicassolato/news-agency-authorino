# frozen_string_literal: true

require 'logger'
require 'json'
require 'securerandom'
require 'base64'

Object.include(Module.new do
  def try(method, *args)
    send(method, *args) if respond_to?(method)
  end
end)

Hash.include(Module.new do
  def symbolize_keys
    transform_keys{ |key| key.to_sym rescue key }
  end

  def reverse_merge(other_hash)
    other_hash.merge(self)
  end
end)

class Storage
  def initialize
    @news = {}
  end

  def list(category)
    @news[category]&.values || []
  end

  def add(category, article)
    @news[category] ||= {}
    @news[category][article.id] = article
  end

  def get(category, article_id)
    @news.dig(category, article_id)
  end

  def delete(category, article_id)
    @news[category]&.delete(article_id)
  end

  def exists?(article_id)
    @news.values.flat_map(&:keys).include?(article_id)
  end
end

ATTRIBUTES = %i[title body date author user_id].freeze

class Article < Struct.new(:id, *ATTRIBUTES, keyword_init: true)
  def self.create(**params)
    new(**params.merge(id: SecureRandom.uuid))
  end

  def to_json
    to_h.to_json
  end
end

class RackApp
  def initialize
    @storage = Storage.new
    @logger = Logger.new(STDOUT)
  end

  attr_reader :storage, :logger

  def call(env)
    request = Rack::Request.new(env)

    request_method = request.request_method
    request_path = request.path
    request_query_string = request.query_string
    request_query_string = nil if request_query_string.empty?

    _, category, article_id = request_path.split('/')

    wristband_token = env['HTTP_X_EXT_AUTH_WRISTBAND']
    wristband_token = nil if wristband_token == 'null'
    extra_headers = wristband_token ? {'X-Ext-Auth-Wristband' => wristband_token} : {}

    response = case request_method
               when 'GET'
                 if article_id.to_s.empty?
                  respond_with(storage.list(category).map(&:to_h), extra_headers: extra_headers)
                else
                  respond_with(storage.get(category, article_id), extra_headers: extra_headers)
                 end
               when 'POST'
                 params = JSON.parse(request.body.read).symbolize_keys.slice(*ATTRIBUTES)
                 date = Time.now
                 author, user_id = if wristband_token
                                     wristband_payload = JSON.parse(Base64.decode64(wristband_token.split('.')[1]))
                                     wristband_payload.values_at('name', 'sub')
                                   else
                                     ['Unknown', nil]
                                   end

                 article = loop do # prevents duplicate article id
                   article = Article.create(params.merge(date: date, author: author, user_id: user_id))
                   break article unless storage.exists?(article.id)
                 end

                 respond_with(storage.add(category, article), extra_headers: extra_headers)
               when 'DELETE'
                 respond_with(storage.delete(category, article_id), extra_headers: extra_headers)
               else
                 render :not_found
               end
  rescue StandardError => e
    response = render(e.try(:status) || :server_error, body: e.message)
  ensure
    logger.info "#{request_method} #{[request_path, request_query_string].compact.join('?')} => #{response.first}"
  end

  protected

  def json_response(body)
    [{'Content-Type' => 'application/json'}, [body.to_json]]
  end

  def render_ok(body)
    [200, *json_response(body)]
  end

  def render_not_found(*)
    [404, *json_response(error: 'Not found')]
  end

  def render_server_error(message)
    [500, *json_response(error: message)]
  end

  def render(status, body: nil)
    send("render_#{status}", body)
  end

  def respond_with(object, extra_headers: {})
    return render(:not_found) unless object
    status, headers, body = render(:ok, body: object)
    [status, headers.merge(extra_headers), body]
  end
end

run(RackApp.new)
