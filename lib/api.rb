# frozen_string_literal: true

require 'net/http'
require 'uri'
require_relative '../config/settings'

class Api
  def messages_send(params)
    uri = URI.parse('https://api.vk.com/method/messages.send')
    params[:access_token] = Settings::ACCESS_TOKEN
    params[:v] = '5.199'
    params[:random_id] ||= rand(1_000_000..9_999_999)
    uri.query = URI.encode_www_form(params)
    Net::HTTP.get_response(uri)
  end
end