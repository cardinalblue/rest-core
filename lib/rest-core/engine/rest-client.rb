
require 'restclient'
require 'rest-core/patch/rest-client'

require 'rest-core/engine/future/future'
require 'rest-core/middleware'

class RestCore::RestClient
  include RestCore::Middleware

  def add_path_method_if_needed params
    params.reduce({}) do |new_params, key, value|
      new_value = if value.is_a?(Hash)
        add_path_method_if_needed value
      elsif value.is_a?(Array)
        value.map do |e|
          add_path_method_if_needed e
        end
      else
        if value.respond_to?(:read) && !value.respond_to?(:path)
          def value.path
            "#{rand(65535)}"
          end
        end
        value
      end

      new_params[key] = new_value
      new_params
    end
  end

  def call env, &k
    future  = Future::FutureThread.new(env, k, env[ASYNC])

    t = future.wrap{ # we can implement thread pool in the future
      begin
        # This is to fix an inconvenient design in RestClient.
        # In particular, RestClient::Payload requires IO objects in the payload to not only
        # respond_to? `read`, but also `path`.
        # This excludes StringIO objects which is unnecessary.
        payload = add_path_method_if_needed(env[REQUEST_PAYLOAD])

        res = ::RestClient::Request.execute(:method  => env[REQUEST_METHOD ],
                                            :url     => request_uri(env)    ,
                                            :payload => payload,
                                            :headers => env[REQUEST_HEADERS],
                                            :max_redirects => 0)
        future.on_load(res.body, res.code, normalize_headers(res.raw_headers))

      rescue ::RestClient::Exception => e
        if res = e.response
          # we don't want to raise an exception for 404 requests
          future.on_load(res.body, res.code,
            normalize_headers(res.raw_headers))
        else
          future.on_error(e)
        end
      rescue Exception => e
        future.on_error(e)
      end
    }

    env[TIMER].on_timeout{
      t.kill
      future.on_error(env[TIMER].error)
    } if env[TIMER]

    env.merge(RESPONSE_BODY    => future.proxy_body,
              RESPONSE_STATUS  => future.proxy_status,
              RESPONSE_HEADERS => future.proxy_headers,
              FUTURE           => future)
  end

  def normalize_headers raw_headers
    raw_headers.inject({}){ |r, (k, v)|
      r[k.to_s.upcase.tr('-', '_')] = if v.kind_of?(Array) && v.size == 1
                                        v.first
                                      else
                                        v
                                      end
      r
    }
  end
end
