require 'net/http'
require 'uri'
require 'json'
require 'pstore'
require_relative 'quiz'
require_relative 'config/settings'

$db = PStore.new('quiz_data.pstore')
quiz_engine = Quiz.new

puts "🤖 Бот запускается..."
puts "📚 Загружено вопросов: #{quiz_engine.instance_variable_get(:@question_manager).questions_count}"

class Api
  def messages_send(params)
    uri = URI.parse("https://api.vk.com/method/messages.send")
    params[:access_token] = Settings::ACCESS_TOKEN
    params[:v] = '5.199'
    params[:random_id] ||= rand(1000000..9999999)
    uri.query = URI.encode_www_form(params)
    Net::HTTP.get_response(uri)
  end
end

class Event
  attr_reader :message, :api
  def initialize(message_data)
    @message = Message.new(message_data)
    @api = Api.new
  end
  def answer(text)
    @api.messages_send(peer_id: @message.peer_id, message: text)
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

def get_longpoll_server
  uri = URI.parse("https://api.vk.com/method/groups.getLongPollServer")
  params = { group_id: Settings::GROUP_ID, access_token: Settings::ACCESS_TOKEN, v: '5.199' }
  uri.query = URI.encode_www_form(params)
  response = Net::HTTP.get_response(uri)
  data = JSON.parse(response.body)
  if data['error']
    puts "❌ Ошибка Long Poll: #{data['error']['error_msg']}"
    exit
  end
  data['response']
end

puts "✅ Бот успешно запущен и слушает сообщения!"

lp_data = get_longpoll_server
server = lp_data['server']
key = lp_data['key']
ts = lp_data['ts']

puts "📡 Подключен к серверу Long Poll"

loop do
  begin
    server_url = server.start_with?('https://') ? server : "https://#{server}"
    uri = URI.parse("#{server_url}?act=a_check&key=#{key}&ts=#{ts}&wait=25&mode=2&version=3")
    
    response = Net::HTTP.get_response(uri)
    events = JSON.parse(response.body)
    
    if events['failed']
      puts "🔄 Переподключение..."
      sleep(2)
      lp_data = get_longpoll_server
      server = lp_data['server']
      key = lp_data['key']
      ts = lp_data['ts']
      next
    end
    
    if events['updates']
      events['updates'].each do |update|
        if update['type'] == 'message_new'
          message = update['object']['message']
          
          # Пропускаем исходящие
          next if message['out'] == 1
          
          peer_id = message['peer_id']
          from_id = message['from_id']
          text = message['text']
          action = message['action']
          
          puts "📨 Сообщение от #{from_id}: #{text}"
          
          message_data = { 'peer_id' => peer_id, 'from_id' => from_id, 'text' => text }
          event = Event.new(message_data)
          
          # Приветствие при добавлении бота в чат
          if action && action['type'] == 'chat_invite_user' && action['member_id'] == -Settings::GROUP_ID
            quiz_engine.welcome_message(event)
            next
          end
          
          case text.to_s
          when '/start', '/help'
            quiz_engine.welcome_message(event)
          when /^\/quiz(\s+(.+))?$/
            match = text.match(/^\/quiz(\s+(.+))?$/)
            theme = match[2] if match[2]
            quiz_engine.start_fast_quiz(event, theme)
          when '/themes'
            quiz_engine.show_themes(event)
          when /^\/tournament(\s+(\d+))?$/
            match = text.match(/^\/tournament(\s+(\d+))?$/)
            rounds = match[2] ? match[2].to_i : 5
            rounds = [[rounds, 3].max, 10].min
            quiz_engine.start_tournament(event, rounds)
          when '/join'
            quiz_engine.join_tournament(event)
          when '/tournament_start'
            quiz_engine.begin_tournament_rounds(event)
          when '/rating'
            quiz_engine.show_rating(event)
          when '/stats'
            quiz_engine.show_stats(event)
          else
            tournament = quiz_engine.instance_variable_get(:@tournaments)[peer_id]
            
            if tournament && tournament[:status] == :in_progress
              quiz_engine.handle_tournament_answer(event)
            else
              quiz_engine.handle_answer(event)
            end
          end
        end
      end
    end
    
    ts = events['ts'] if events['ts']
    
  rescue => e
    puts "⚠️ Ошибка: #{e.message}"
    sleep(5)
  end
end