# frozen_string_literal: true

require_relative 'api'

class Event
  attr_reader :message, :api

  def initialize(message_data)
    @message = Message.new(message_data)
    @api = Api.new
  end

  def answer(text, keyboard: nil)
    params = { peer_id: @message.peer_id, message: text }
    params[:keyboard] = keyboard.to_json if keyboard
    @api.messages_send(params)
  end

  class Message
    attr_reader :peer_id, :from_id, :text

    def initialize(data)
      @peer_id = data['peer_id']
      @from_id = data['from_id']
      @text = data['text']
    end
  end
end