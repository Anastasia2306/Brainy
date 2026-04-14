require 'vk_cozy'
require 'vkontakte_api'
require 'pstore'
require_relative 'quiz'
require_relative 'config/settings'

# Инициализация бота
bot = VkCozy::Bot.new(Settings::ACCESS_TOKEN)

# Инициализация VK API для дополнительных операций
vk = VkontakteApi::Client.new(Settings::ACCESS_TOKEN)

# Хранилище данных
$db = PStore.new('quiz_data.pstore')

# Экземпляр класса с логикой викторины
quiz_engine = Quiz.new

puts " Бот запускается..."
puts " Загружено вопросов: #{quiz_engine.instance_variable_get(:@question_manager).questions_count}"

# ОБРАБОТЧИКИ КОМАНД

# Команда /start
bot.on.message_handler(Filter::Text.new('/start'), -> (event) {
  event.answer(
    " Привет! Я бот для викторин и квизов!\n\n" \
    " Доступные команды:\n" \
    " Быстрый режим:\n" \
    "  /quiz - случайный вопрос\n" \
    "  /quiz [тема] - вопрос по теме\n" \
    "  /themes - список тем\n\n" \
    " Турнирный режим:\n" \
    "  /tournament - создать турнир\n" \
    "  /join - присоединиться\n\n" \
    " Статистика:\n" \
    "  /rating - общий рейтинг\n" \
    "  /stats - статистика бота\n" \
    "  /help - это сообщение"
  )
})

# Команда /help
bot.on.message_handler(Filter::Text.new('/help'), -> (event) {
  event.answer(
    " КАК ИГРАТЬ:\n\n" \
    "Быстрый режим:\n" \
    "1. Напишите /quiz для случайного вопроса\n" \
    "2. Первый правильный ответ получает 10 очков\n\n" \
    "Турнирный режим:\n" \
    "1. Напишите /tournament для создания турнира\n" \
    "2. Участники пишут /join\n" \
    "3. Организатор пишет /tournament_start\n" \
    "4. После каждого вопроса 30 секунд на ответ\n\n" \
    "Команды с параметрами:\n" \
    "/quiz История - вопрос по истории\n" \
    "/tournament 7 - турнир на 7 раундов"
  )
})

# Команда /quiz - запуск быстрой викторины
bot.on.message_handler(Filter::Text.new(/^\/quiz(\s+(.+))?$/), -> (event) {
  match = event.message.text.match(/^\/quiz(\s+(.+))?$/)
  theme = match[2] if match[2]
  quiz_engine.start_fast_quiz(event, theme)
})

# Команда /themes - показать все темы
bot.on.message_handler(Filter::Text.new('/themes'), -> (event) {
  quiz_engine.show_themes(event)
})

# Команда /tournament - создание турнира
bot.on.message_handler(Filter::Text.new(/^\/tournament(\s+(\d+))?$/), -> (event) {
  match = event.message.text.match(/^\/tournament(\s+(\d+))?$/)
  rounds = match[2] ? match[2].to_i : 5
  rounds = [[rounds, 3].max, 10].min  # Ограничиваем от 3 до 10 раундов
  quiz_engine.start_tournament(event, rounds)
})

# Команда /join - присоединиться к турниру
bot.on.message_handler(Filter::Text.new('/join'), -> (event) {
  quiz_engine.join_tournament(event)
})

# Команда /tournament_start - начать раунды турнира
bot.on.message_handler(Filter::Text.new('/tournament_start'), -> (event) {
  quiz_engine.begin_tournament_rounds(event)
})

# Команда /rating - показать рейтинг
bot.on.message_handler(Filter::Text.new('/rating'), -> (event) {
  quiz_engine.show_rating(event)
})

# Команда /stats - статистика
bot.on.message_handler(Filter::Text.new('/stats'), -> (event) {
  quiz_engine.show_stats(event)
})

# Обработка ответов (все остальные текстовые сообщения)
bot.on.message_handler(Filter::Text.new(/.*/), -> (event) {
  # Сначала проверяем, не ответ ли это на турнир
  tournament = quiz_engine.instance_variable_get(:@tournaments)[event.message.peer_id]
  
  if tournament && tournament[:status] == :in_progress
    quiz_engine.handle_tournament_answer(event)
  else
    # Иначе проверяем быструю викторину
    quiz_engine.handle_answer(event)
  end
})

# Обработка ошибок
bot.on.event_handler(Filter::Any.new, -> (event) {
  if event.is_a?(VkCozy::ErrorEvent)
    puts " Ошибка: #{event.error.message}"
  end
})

puts " Бот успешно запущен и слушает сообщения!"

# Запуск бота
bot.run_polling()