require 'pstore'
require_relative 'question_manager'
require_relative 'config/settings'

class Quiz
  def initialize
    @active_quizzes = {}  # chat_id => текущая викторина
    @tournaments = {}     # chat_id => турнир
    @question_manager = QuestionManager.new
  end
  
  # ========== ПРИВЕТСТВИЕ ПРИ ДОБАВЛЕНИИ В ЧАТ ==========
  
  def welcome_message(event)
    event.answer(
      "🎯 Привет! Я бот для викторин и квизов!\n\n" \
      "📋 Доступные команды:\n" \
      "🎮 Быстрый режим:\n" \
      "  /quiz - случайный вопрос\n" \
      "  /quiz [тема] - вопрос по теме\n" \
      "  /themes - список тем\n\n" \
      "🏆 Турнирный режим:\n" \
      "  /tournament - создать турнир\n" \
      "  /join - присоединиться к турниру\n\n" \
      "📊 Статистика:\n" \
      "  /rating - общий рейтинг\n" \
      "  /stats - статистика бота"
    )
  end
  
  # ========== БЫСТРЫЙ РЕЖИМ ==========
  
  def start_fast_quiz(event, theme = nil)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    
    # Проверяем, не запущена ли уже викторина
    if @active_quizzes[chat_id]
      event.answer("❌ В этом чате уже идет викторина! Дождитесь окончания.")
      return
    end
    
    # Получаем случайный вопрос
    question = @question_manager.get_random_question(theme)
    
    if question.nil?
      event.answer("❌ Вопросы не найдены" + (theme ? " по теме '#{theme}'" : ""))
      return
    end
    
    # Запускаем викторину
    @active_quizzes[chat_id] = {
      question: question,
      start_time: Time.now,
      theme: theme,
      attempts: {},
      answered: false  # Флаг, что на вопрос уже ответили
    }
    
    # Отправляем вопрос
    theme_text = theme ? "\n📚 Тема: #{theme}" : ""
    event.answer("🎯 БЫСТРАЯ ВИКТОРИНА!#{theme_text}\n\n❓ #{question[:question]}\n\n⏱ У вас #{Settings::ANSWER_TIMEOUT} секунд!")
    
    # Таймер на завершение по времени
    Thread.new do
      sleep(Settings::ANSWER_TIMEOUT)
      if @active_quizzes[chat_id] && !@active_quizzes[chat_id][:answered]
        quiz = @active_quizzes.delete(chat_id)
        if quiz
          event.api.messages_send(
            peer_id: chat_id,
            message: "⏰ Время вышло!\nПравильный ответ: #{quiz[:question][:answer]}",
            random_id: rand(1000000..9999999)
          )
        end
      end
    end
  end
  
  def handle_answer(event)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    user_answer = event.message.text.strip
    
    # Проверяем, запущена ли викторина
    current_quiz = @active_quizzes[chat_id]
    return false unless current_quiz
    
    # Проверяем, не ответили ли уже правильно
    return false if current_quiz[:answered]
    
    # Проверяем, не отвечал ли уже пользователь
    if current_quiz[:attempts][user_id]
      # Не отправляем сообщение, чтобы не спамить
      return false
    end
    
    question = current_quiz[:question]
    correct_answer = question[:answer].to_s.strip
    
    # Запоминаем попытку
    current_quiz[:attempts][user_id] = true
    
    # Сравниваем ответы (игнорируем регистр и лишние пробелы)
    if user_answer.downcase.strip == correct_answer.downcase.strip
      # Правильный ответ!
      current_quiz[:answered] = true
      
      event.answer("🎉 @id#{user_id}, ВЕРНО! Ответ: #{question[:answer]}\n+10 очков!")
      
      award_points(chat_id, user_id, Settings::POINTS_PER_ANSWER)
      @active_quizzes.delete(chat_id)
      return true
    else
      # Неверный ответ - не отправляем сообщение, чтобы не засорять чат
      # Можно раскомментировать для отладки:
      # event.answer("❌ @id#{user_id}, неверно. Пробуйте дальше!")
      return false
    end
  end
  
  # ========== ТУРНИРНЫЙ РЕЖИМ ==========
  
  def start_tournament(event, rounds = 5)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    
    if @tournaments[chat_id]
      event.answer("❌ В этом чате уже идет турнир!")
      return
    end
    
    if @question_manager.questions_count < rounds
      event.answer("❌ Недостаточно вопросов для турнира из #{rounds} раундов")
      return
    end
    
    @tournaments[chat_id] = {
      status: :registration,
      creator_id: user_id,
      total_rounds: rounds,
      current_round: 0,
      players: {},
      scores: {},
      questions: []
    }
    
    event.answer(
      "🏆 ТУРНИР НАЧИНАЕТСЯ!\n\n" \
      "📋 Регистрация открыта!\n" \
      "👉 Напишите '/join' для участия\n" \
      "👉 Организатор напишите '/tournament_start' когда все будут готовы\n" \
      "📊 Раундов: #{rounds}"
    )
  end
  
  def join_tournament(event)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    
    tournament = @tournaments[chat_id]
    
    unless tournament
      event.answer("❌ Сейчас нет активного турнира. Создайте его командой /tournament")
      return
    end
    
    if tournament[:status] != :registration
      event.answer("❌ Турнир уже начался, регистрация закрыта!")
      return
    end
    
    if tournament[:players][user_id]
      event.answer("⚠ @id#{user_id}, вы уже в списке участников!")
    else
      tournament[:players][user_id] = {
        joined_at: Time.now
      }
      tournament[:scores][user_id] = 0
      
      event.answer("✅ @id#{user_id} присоединился к турниру! Всего участников: #{tournament[:players].size}")
    end
  end
  
  def begin_tournament_rounds(event)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    
    tournament = @tournaments[chat_id]
    return unless tournament
    
    if tournament[:creator_id] != user_id
      event.answer("❌ Только организатор может начать турнир!")
      return
    end
    
    if tournament[:players].empty?
      event.answer("❌ Нет зарегистрированных участников!")
      return
    end
    
    tournament[:status] = :in_progress
    tournament[:questions] = (0...tournament[:total_rounds]).map { 
      @question_manager.get_random_question 
    }
    
    event.answer(
      "🎮 ТУРНИР НАЧИНАЕТСЯ!\n" \
      "👥 Участников: #{tournament[:players].size}\n" \
      "📊 Раундов: #{tournament[:total_rounds]}\n\n" \
      "Первый вопрос через 3 секунды..."
    )
    
    sleep(3)
    start_next_round(chat_id, event.api)
  end
  
  def start_next_round(chat_id, api)
    tournament = @tournaments[chat_id]
    return unless tournament && tournament[:status] == :in_progress
    
    tournament[:current_round] += 1
    
    if tournament[:current_round] > tournament[:total_rounds]
      finish_tournament(chat_id, api)
      return
    end
    
    question = tournament[:questions][tournament[:current_round] - 1]
    tournament[:current_question] = question
    tournament[:round_answers] = {}
    tournament[:round_answered] = false
    
    api.messages_send(
      peer_id: chat_id,
      message: "📌 Раунд #{tournament[:current_round]}/#{tournament[:total_rounds]}\n\n❓ #{question[:question]}\n\n⏱ 30 секунд на ответ!",
      random_id: rand(1000000..9999999)
    )
    
    # Таймер на следующий раунд
    Thread.new do
      sleep(30)
      if @tournaments[chat_id] && @tournaments[chat_id][:status] == :in_progress
        process_tournament_round(chat_id, api)
      end
    end
  end
  
  def process_tournament_round(chat_id, api)
    tournament = @tournaments[chat_id]
    return unless tournament
    
    question = tournament[:current_question]
    correct_answer = question[:answer].to_s.strip
    
    # Подсчет результатов раунда
    round_results = "📊 Результаты раунда #{tournament[:current_round]}:\n\n"
    round_results += "✅ Правильный ответ: #{correct_answer}\n\n"
    
    tournament[:players].each do |user_id, _|
      player_answer = tournament[:round_answers][user_id]
      
      if player_answer && player_answer.downcase.strip == correct_answer.downcase.strip
        tournament[:scores][user_id] += Settings::POINTS_PER_ANSWER
        round_results += "✓ @id#{user_id}: +#{Settings::POINTS_PER_ANSWER} очков\n"
      else
        round_results += "✗ @id#{user_id}: 0 очков\n"
      end
    end
    
    round_results += "\n🏆 Текущий счет:\n"
    sorted_scores = tournament[:scores].sort_by { |_, score| -score }
    sorted_scores.each_with_index do |(user_id, score), index|
      round_results += "#{index + 1}. @id#{user_id}: #{score} очков\n"
    end
    
    api.messages_send(peer_id: chat_id, message: round_results, random_id: rand(1000000..9999999))
    
    sleep(5)
    start_next_round(chat_id, api)
  end
  
  def handle_tournament_answer(event)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    user_answer = event.message.text.strip
    
    tournament = @tournaments[chat_id]
    return false unless tournament && tournament[:status] == :in_progress
    
    # Проверяем, участник ли это
    unless tournament[:players][user_id]
      return false
    end
    
    # Проверяем, не ответили ли уже правильно в этом раунде
    return false if tournament[:round_answered]
    
    # Проверяем, не отвечал ли уже этот пользователь
    return false if tournament[:round_answers][user_id]
    
    correct_answer = tournament[:current_question][:answer].to_s.strip
    
    tournament[:round_answers][user_id] = user_answer
    
    if user_answer.downcase.strip == correct_answer.downcase.strip
      tournament[:round_answered] = true
      event.answer("🎉 @id#{user_id} ответил верно!")
    end
    
    true
  end
  
  def finish_tournament(chat_id, api)
    tournament = @tournaments.delete(chat_id)
    return unless tournament
    
    # Сохраняем результаты в общий рейтинг
    $db.transaction do
      $db[chat_id] ||= {}
      
      tournament[:scores].each do |user_id, score|
        $db[chat_id][user_id] ||= 0
        $db[chat_id][user_id] += score
      end
    end
    
    # Формируем финальное сообщение
    message = "🏆 ТУРНИР ЗАВЕРШЕН! 🏆\n\n🥇 Итоговые результаты:\n\n"
    
    sorted_scores = tournament[:scores].sort_by { |_, score| -score }
    medals = ['🥇', '🥈', '🥉']
    
    sorted_scores.each_with_index do |(user_id, score), index|
      medal = index < 3 ? medals[index] : "#{index + 1}."
      message += "#{medal} @id#{user_id}: #{score} очков\n"
    end
    
    message += "\n🎊 Поздравляем победителей!"
    
    api.messages_send(peer_id: chat_id, message: message, random_id: rand(1000000..9999999))
  end
  
  # ========== РЕЙТИНГ ==========
  
  def show_rating(event)
    chat_id = event.message.peer_id
    
    rating_text = "🏆 ОБЩИЙ РЕЙТИНГ ИГРОКОВ 🏆\n\n"
    
    $db.transaction(true) do
      chat_rating = $db.fetch(chat_id, {})
      
      if chat_rating.empty?
        rating_text += "Пока никто не набрал очков. Сыграйте в викторину!"
      else
        sorted = chat_rating.sort_by { |_, score| -score }.first(Settings::RATING_LIMIT)
        
        sorted.each_with_index do |(user_id, score), index|
          medal = case index
                 when 0 then '🥇'
                 when 1 then '🥈'
                 when 2 then '🥉'
                 else "#{index + 1}."
                 end
          
          rating_text += "#{medal} @id#{user_id} — #{score} очков\n"
        end
      end
    end
    
    event.answer(rating_text)
  end
  
  def show_themes(event)
    themes = @question_manager.get_all_themes
    counts = themes.map { |t| [t, @question_manager.questions_by_theme(t).size] }
    
    message = "📚 Доступные темы:\n\n"
    counts.each do |theme, count|
      message += "• #{theme} (#{count} вопросов)\n"
    end
    
    event.answer(message)
  end
  
  def show_stats(event)
    chat_id = event.message.peer_id
    
    stats = "📊 СТАТИСТИКА БОТА\n\n"
    stats += "📝 Всего вопросов в базе: #{@question_manager.questions_count}\n"
    stats += "🏷 Тем: #{@question_manager.get_all_themes.size}\n"
    
    $db.transaction(true) do
      active_players = $db.fetch(chat_id, {}).size
      stats += "👥 Игроков в рейтинге: #{active_players}\n"
    end
    
    stats += "🎮 Активных игр сейчас: #{@active_quizzes.size}\n"
    stats += "🏆 Активных турниров: #{@tournaments.size}"
    
    event.answer(stats)
  end
  
  private
  
  def award_points(chat_id, user_id, points)
    $db.transaction do
      $db[chat_id] ||= {}
      $db[chat_id][user_id] ||= 0
      $db[chat_id][user_id] += points
    end
  end
end