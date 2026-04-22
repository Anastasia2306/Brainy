require 'net/http'
require 'uri'
require 'json'
require 'pstore'
require_relative 'quiz'
require_relative 'config/settings'

# Инициализация хранилища
$db = PStore.new('quiz_data.pstore')

# Экземпляр класса с логикой викторины
quiz_engine = Quiz.new

puts "🤖 Бот запускается..."
puts "📚 Загружено вопросов: #{quiz_engine.instance_variable_get(:@question_manager).questions_count}"

# Класс для отправки сообщений
class Api
  def messages_send(params)
    uri = URI.parse("https://api.vk.com/method/messages.send")
    params[:access_token] = Settings::ACCESS_TOKEN
    params[:v] = '5.199'
    params[:random_id] ||= rand(1000000..9999999)
    
    uri.query = URI.encode_www_form(params)
    response = Net::HTTP.get_response(uri)
    puts "📤 Ответ отправлен"
  rescue => e
    puts "❌ Ошибка отправки: #{e.message}"
  end
  
  def users_get(params)
    [{'first_name' => 'Участник', 'last_name' => ''}]
  end
end

# Эмуляция event объекта
class Event
  attr_reader :message, :api
  
  def initialize(message_data)
    @message = Message.new(message_data)
    @api = Api.new
  end
  
  def answer(text)
    @api.messages_send(
      peer_id: @message.peer_id,
      message: text
    )
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

# Получение Long Poll сервера
def get_longpoll_server
  uri = URI.parse("https://api.vk.com/method/groups.getLongPollServer")
  params = {
    group_id: Settings::GROUP_ID,
    access_token: Settings::ACCESS_TOKEN,
    v: '5.199'
  }
  uri.query = URI.encode_www_form(params)
  
  response = Net::HTTP.get_response(uri)
  data = JSON.parse(response.body)
  
  if data['error']
    puts "❌ Ошибка Long Poll: #{data['error']['error_msg']}"
    puts "   Проверьте, что в настройках сообщества включён Long Poll API"
    puts "   и токен имеет доступ к сообщениям сообщества."
    exit
  end
  
  data['response']
end

puts "✅ Бот успешно запущен и слушает сообщения!"

# Получаем сервер Long Poll
lp_data = get_longpoll_server
server = lp_data['server']
key = lp_data['key']
ts = lp_data['ts']

puts "📡 Подключен к серверу Long Poll"

# Основной цикл обработки сообщений
loop do
  begin
    # Формируем правильный URL для Long Poll
    server_url = server.start_with?('https://') ? server : "https://#{server}"
    uri = URI.parse("#{server_url}?act=a_check&key=#{key}&ts=#{ts}&wait=25&mode=2&version=3")
    
    response = Net::HTTP.get(uri)
    events = JSON.parse(response)
    
    # Обработка сбоя Long Poll
    if events['failed']
      puts "🔄 Переподключение Long Poll (failed: #{events['failed']})..."
      sleep(2)
      lp_data = get_longpoll_server
      server = lp_data['server']
      key = lp_data['key']
      ts = lp_data['ts']
      puts "📡 Переподключено к серверу"
      next
    end
    
    # Обработка новых сообщений
    if events['updates'] && !events['updates'].empty?
      events['updates'].each do |update|
        # update[0] - тип события, 4 = новое сообщение
        if update[0] == 4
          message_id = update[1]
          flags = update[2]
          peer_id = update[3]
          timestamp = update[4]
          text = update[5]
          from_id = update[6]['from']
          
          # Пропускаем исходящие сообщения (flags & 2)
          next if (flags & 2) != 0
          
          puts "📨 Сообщение от #{from_id}: #{text}"
          
          message_data = {
            'peer_id' => peer_id,
            'from_id' => from_id,
            'text' => text
          }
          
          event = Event.new(message_data)
          
          # Обработка команд
          case text.to_s
          when '/start', '/help'
            event.answer(
              "🎯 Привет! Я бот для викторин и квизов!\n\n" \
              "📋 Доступные команды:\n" \
              "🎮 Быстрый режим:\n" \
              "  /quiz - случайный вопрос\n" \
              "  /quiz [тема] - вопрос по теме\n" \
              "  /themes - список тем\n\n" \
              "🏆 Турнирный режим:\n" \
              "  /tournament - создать турнир\n" \
              "  /join - присоединиться\n\n" \
              "📊 Статистика:\n" \
              "  /rating - общий рейтинг\n" \
              "  /stats - статистика бота"
            )
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
    
    # Обновляем ts для следующего запроса
    ts = events['ts'] if events['ts']
    
  rescue JSON::ParserError => e
    puts "⚠️ Ошибка парсинга JSON: #{e.message}"
    sleep(5)
  rescue => e
    puts "⚠️ Ошибка: #{e.message}"
    sleep(5)
    # При ошибке пытаемся переподключиться
    begin
      lp_data = get_longpoll_server
      server = lp_data['server']
      key = lp_data['key']
      ts = lp_data['ts']
      puts "📡 Переподключено после ошибки"
    rescue => reconnect_error
      puts "❌ Не удалось переподключиться: #{reconnect_error.message}"
    end
  end
end