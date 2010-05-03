
require 'rest_client'

require 'cgi'

class RestGraph < Struct.new(:access_token, :graph_server, :fql_server,
                             :accept, :lang, :auto_decode, :app_id, :secret)
  def initialize o = {}
    self.access_token = o[:access_token]
    self.graph_server = o[:graph_server] || 'https://graph.facebook.com/'
    self.fql_server   = o[:fql_server]   || 'https://api.facebook.com/'
    self.accept       = o[:accept] || 'text/javascript'
    self.lang         = o[:lang]   || 'en-us'
    self.auto_decode  = o.key?(:auto_decode) ? o[:auto_decode] : true

    if auto_decode
      begin
        require 'json'
      rescue LoadError
        require 'json_pure'
      end
    end
  end

  def get    path, opts = {}
    request(graph_server, path, opts, :get)
  end

  def delete path, opts = {}
    request(graph_server, path, opts, :delete)
  end

  def post   path, payload, opts = {}
    request(graph_server, path, opts, :post, payload)
  end

  def put    path, payload, opts = {}
    request(graph_server, path, opts, :put,  payload)
  end

  def fql query, opts = {}
    request(fql_server, 'method/fql.query',
      {:query  => query, :format => 'json'}.merge(opts), :get)
  end

  private
  def request server, path, opts, method, payload = nil
    post_request(
      RestClient::Resource.new(server)[path + build_query_string(opts)].
      send(method, *[payload, build_headers].compact))
  rescue RestClient::InternalServerError => e
    post_request(e.http_body)
  end

  def build_query_string q = {}
    query = q.merge(access_token ? {:access_token => access_token} : {})
    return '' if query.empty?
    return '?' + query.map{ |(k, v)| "#{k}=#{CGI.escape(v)}" }.join('&')
  end

  def build_headers
    headers = {}
    headers['Accept']          = accept if accept
    headers['Accept-Language'] = lang   if lang
    headers
  end

  def post_request result
    auto_decode ? JSON.parse(result) : result
  end
end
