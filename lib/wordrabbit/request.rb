module Wordrabbit

  class Request
    require 'uri'
    require 'addressable/uri'
    require 'typhoeus'
    require "wordrabbit/version"

    attr_accessor :host, :path, :format, :params, :body, :http_method, :headers

    # All requests must have an HTTP method and a path
    # Optionals parameters are :params, :headers, :body, :format, :host
    # 
    def initialize(http_method, path, attributes={})
      attributes[:format] ||= "json"
      attributes[:host] ||= Wordrabbit.configuration.base_uri
      attributes[:params] ||= {}

      # Set default headers
      default_headers = {
        'User-Agent' => "Wordrabbit Ruby Gem #{Wordrabbit::VERSION}",
        'Content-Type' => "application/#{attributes[:format].downcase}",
        :api_key => Wordrabbit.configuration.api_key
      }

      # If a nil/blank api_key was passed in, remove it from the headers, even if the override value is nil/blank
      if attributes[:headers].present? && attributes[:headers].has_key?(:api_key)
        default_headers.delete(:api_key)
      end
      
      # If nil/blank api_key was passed in in the params, it overrides both the default
      # headers and the argument headers
      if attributes[:params].present? && attributes[:params].has_key?(:api_key)
        default_headers.delete(:api_key)
        attributes[:headers].delete(:api_key) if attributes[:headers].present?
      end
      
      # Merge argument headers into defaults
      attributes[:headers] = default_headers.merge(attributes[:headers] || {})
      
      # Stick in the auth token if there is one
      if Wordrabbit.authenticated?
        attributes[:headers].merge!({:auth_token => Wordrabbit.configuration.auth_token})
      end
            
      self.http_method = http_method.to_sym
      self.path = path
      attributes.each do |name, value|
        send("#{name.to_s.underscore.to_sym}=", value)
      end
    end

    # Construct a base URL
    def url
      u = Addressable::URI.new
      u.host = self.host.sub(/\/$/, '') # Remove trailing slash
      u.path = self.interpreted_path
      u.scheme = "http" # For some reason this must be set _after_ host, otherwise Addressable gets upset
      u.to_s
    end

    # Iterate over the params hash, injecting any path values into the path string
    # e.g. /word.{format}/{word}/entries => /word.json/cat/entries
    def interpreted_path
      p = self.path
      self.params.each_pair do |key, value|
        p = p.gsub("{#{key}}", value.to_s)
      end

      # Stick a .{format} placeholder into the path if there isn't
      # one already or an actual format like json or xml
      # e.g. /words/blah => /words.{format}/blah
      unless ['.json', '.xml', '{format}'].any? {|s| p.downcase.include? s }
        p = p.sub(/^(\/?\w+)/, "\\1.#{format}")
      end

      p = p.sub("{format}", self.format)
      URI.encode(p)
    end
  
    # Massage the request body into a state of readiness
    # If body is a hash, camelize all keys then convert to a json string
    #
    def body=(value)      
      if value.is_a?(Hash)
        value = value.inject({}) do |memo, (k,v)|
          memo[k.to_s.camelize(:lower).to_sym] = v
          memo
        end
      end
      @body = value
    end
  
    # Iterate over all params,
    # .. removing the ones that are part of the path itself.
    # .. stringifying values so Addressable doesn't blow up.
    # .. obfuscating the API key if needed.
    def query_string_params(obfuscated=false)
      qsp = {}
      self.params.each_pair do |key, value|
        next if self.path.include? "{#{key}}"                                   # skip path params
        next if value.blank? && value.class != FalseClass                       # skip empties
        value = "YOUR_API_KEY" if key.to_sym == :api_key && obfuscated          # obscure the API key
        key = key.to_s.camelize(:lower).to_sym unless key.to_sym == :api_key    # api_key is not a camelCased param
        qsp[key] = value.to_s
      end
      qsp
    end
  
    # Construct a query string from the query-string-type params
    def query_string(options={})
    
      # We don't want to end up with '?' as our query string
      # if there aren't really any params
      return "" if query_string_params.blank?
    
      default_options = {:obfuscated => false}
      options = default_options.merge(options)
    
      qs = Addressable::URI.new
      qs.query_values = self.query_string_params(options[:obfuscated])
      qs.to_s
    end
  
    # Returns full request URL with query string included
    def url_with_query_string(options={})
      default_options = {:obfuscated => false}
      options = default_options.merge(options)
    
      [url, query_string(options)].join('')
    end
  
    def make
      response = case self.http_method.to_sym
      when :get
        Typhoeus::Request.get(
          self.url_with_query_string,
          :headers => self.headers.stringify_keys
        )

      when :post
        Typhoeus::Request.post(
          self.url_with_query_string,
          :body => self.body.to_json,
          :headers => self.headers.stringify_keys
        )

      when :put
        Typhoeus::Request.put(
          self.url_with_query_string,
          :body => self.body.to_json,
          :headers => self.headers.stringify_keys
        )
      
      when :delete
        Typhoeus::Request.delete(
          self.url_with_query_string,
          :body => self.body.to_json,
          :headers => self.headers.stringify_keys
        )
      end
      Response.new(response)
    end
  
    def response
      self.make
    end
  
    def response_code_pretty
      return unless @response.present?
      @response.code.to_s    
    end
  
    def response_headers_pretty
      return unless @response.present?
      # JSON.pretty_generate(@response.headers).gsub(/\n/, '<br/>') # <- This was for RestClient
      @response.headers.gsub(/\n/, '<br/>') # <- This is for Typhoeus
    end


  end
end