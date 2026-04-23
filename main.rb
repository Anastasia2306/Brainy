require 'net/http'
require 'uri'
require 'json'
require_relative 'config/settings'

puts "🚀 Тестовый бот запущен..."

# Функция отправки сообщения
def send_message(peer_id, text)
  uri = URI.parse("https://api.vk.com/method/messages.send")
  params = {
    peer_id: peer_id,
    message: "Тест: #{text}",
    access_token: Settings::ACCESS_TOKEN,
    v: '5.199',
    random_id: rand(1000000..9999999)
  }
  uri.query = URI.encode_www_form(params)
  response = Net::HTTP.get_response(uri)
  puts "📤 Попытка отправки ответа. Код: #{response.code}"
end

# Получение Long Poll сервера
def get_longpoll_server
  uri = URI.parse("https://api.vk.com/method/messages.getLongPollServer")
  params = {
    need_pts: 0,
    lp_version: 3,
    access_token: Settings::ACCESS_TOKEN,
    v: '5.199'
  }
  uri.query = URI.encode_www_form(params)
  response = Net::HTTP.get_response(uri)
  data = JSON.parse(response.body)
  if data['error']
    puts "❌ Критическая ошибка Long Poll: #{data['error']['error_msg']}"
    exit
  end
  data['response']
end

lp_data = get_longpoll_server
server = lp_data['server']
key = lp_data['key']
ts = lp_data['ts']
puts "📡 Подключены к серверу. Ожидаем сообщений..."

loop do
  begin
    server_url = server.start_with?('https://') ? server : "https://#{server}"
    uri = URI.parse("#{server_url}?act=a_check&key=#{key}&ts=#{ts}&wait=25&version=3")
    
    response = Net::HTTP.get(uri)
    events = JSON.parse(response.body)
    
    if events['failed']
      puts "🔄 Переподключение..."
      sleep(2)
      lp_data = get_longpoll_server
      server = lp_data['server']
      key = lp_data['key']
      ts = lp_data['ts']
      puts "📡 Переподключено"
      next
    end
    
    if events['updates']
      events['updates'].each do |update|
        if update[0] == 4
          flags = update[2]
          peer_id = update[3]
          text = update[5]
          from_id = update[6]['from']
          
          # Пропускаем исходящие
          next if (flags & 2) != 0
          
          puts "📨 Получено от #{from_id}: '#{text}'"
          send_message(peer_id, "Получил твое сообщение: '#{text}'")
        end
      end
    end
    
    ts = events['ts'] if events['ts']
    
  rescue => e
    puts "⚠️ Ошибка в цикле: #{e.message}"
    sleep(5)
  end
end