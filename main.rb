# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'pstore'
require_relative 'lib/quiz'
require_relative 'lib/event'
require_relative 'lib/keyboards'
require_relative 'config/settings'

$db = PStore.new('quiz_data.pstore')
quiz_engine = Quiz.new

puts '🤖 Бот запускается...'
puts "📚 Загружено вопросов: #{quiz_engine.instance_variable_get(:@question_manager).questions_count}"

def get_longpoll_server
  uri = URI.parse('https://api.vk.com/method/groups.getLongPollServer')
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

puts '✅ Бот успешно запущен и слушает сообщения!'

lp_data = get_longpoll_server
server = lp_data['server']
key = lp_data['key']
ts = lp_data['ts']
puts '📡 Подключен к серверу Long Poll'

loop do
  server_url = server.start_with?('https://') ? server : "https://#{server}"
  uri = URI.parse("#{server_url}?act=a_check&key=#{key}&ts=#{ts}&wait=25&mode=2&version=3")

  response = Net::HTTP.get_response(uri)
  events = JSON.parse(response.body)

  if events['failed']
    puts '🔄 Переподключение...'
    sleep(2)
    lp_data = get_longpoll_server
    server = lp_data['server']
    key = lp_data['key']
    ts = lp_data['ts']
    next
  end

  events['updates']&.each do |update|
    next unless update['type'] == 'message_new'

    message = update['object']['message']
    next if message['out'] == 1

    peer_id = message['peer_id']
    from_id = message['from_id']
    text = message['text'].to_s
    action = message['action']

    puts "📨 Сообщение от #{from_id}: #{text}"

    event = Event.new({ 'peer_id' => peer_id, 'from_id' => from_id, 'text' => text })

    # Приветствие при добавлении в чат
    if action && action['type'] == 'chat_invite_user' && (action['member_id'] == -Settings::GROUP_ID)
      puts '   🎉 Бот добавлен в чат!'
      quiz_engine.welcome_message(event, keyboard: Keyboards::MAIN)
      next
    end

    clean_text = text.to_s.gsub(/\[club\d+\|[^\]]+\]\s*/, '').strip

    case clean_text
    when '/start', '/help', '❓ Помощь', 'Помощь'
      quiz_engine.welcome_message(event, keyboard: Keyboards::MAIN)
    when '/quiz', '🎮 Викторина', 'Викторина'
      quiz_engine.start_fast_quiz(event)
    when '/themes', '📚 Темы', 'Темы'
      quiz_engine.show_themes(event)
    when '/tournament', '🏆 Турнир', 'Турнир'
      quiz_engine.start_tournament(event)
      event.answer('Управление турниром:', keyboard: Keyboards::TOURNAMENT)
    when '/join', '➕ Присоединиться', 'Присоединиться'
      quiz_engine.join_tournament(event)
    when '/tournament_start', '🚀 Начать турнир', 'Начать турнир'
      quiz_engine.begin_tournament_rounds(event)
    when '/rating', '⭐ Рейтинг', 'Рейтинг'
      quiz_engine.show_rating(event)
    when '/stats', '📊 Статистика', 'Статистика'
      quiz_engine.show_stats(event)
    when '◀ Назад', 'Назад'
      tournament = quiz_engine.instance_variable_get(:@tournaments)[peer_id]
      if tournament
        quiz_engine.instance_variable_get(:@tournaments).delete(peer_id)
        event.answer('❌ Турнир отменён.')
      end
      event.answer('Главное меню:', keyboard: Keyboards::MAIN)
    else
      tournament = quiz_engine.instance_variable_get(:@tournaments)[peer_id]
      active_quiz = quiz_engine.instance_variable_get(:@active_quizzes)[peer_id]

      if tournament && tournament[:status] == :in_progress
        quiz_engine.handle_tournament_answer(event)
      elsif active_quiz
        quiz_engine.handle_answer(event)
      end
    end
  end

  ts = events['ts'] if events['ts']
rescue StandardError => e
  puts "⚠️ Ошибка: #{e.message}"
  sleep(5)
end