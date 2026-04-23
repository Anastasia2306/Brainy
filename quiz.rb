require 'pstore'
require_relative 'question_manager'
require_relative 'config/settings'

class Quiz
  def initialize
    @active_quizzes = {}  # chat_id => текущая викторина
    @tournaments = {}     # chat_id => турнир
    @question_manager = QuestionManager.new
  end
  
  # ========== ПРИВЕТСТВИЕ ==========
  
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
    
    if @active_quizzes[chat_id]
      event.answer("❌ В этом чате уже идет викторина!")
      return
    end
    
    question = @question_manager.get_random_question(theme)
    
    if question.nil?
      event.answer("❌ Вопросы не найдены" + (theme ? " по теме '#{theme}'" : ""))
      return
    end
    
    @active_quizzes[chat_id] = {
      question: question,
      start_time: Time.now,
      theme: theme,
      attempts: {},
      answered: false
    }
    
    theme_text = theme ? "\n📚 Тема: #{theme}" : ""
    event.answer("🎯 БЫСТРАЯ ВИКТОРИНА!#{theme_text}\n\n❓ #{question[:question]}\n\n⏱ У вас #{Settings::ANSWER_TIMEOUT} секунд!")
    
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
    user_answer = event.message.text.to_s.strip
    
    current_quiz = @active_quizzes[chat_id]
    return false unless current_quiz
    return false if current_quiz[:answered]
    return false if current_quiz[:attempts][user_id]
    
    question = current_quiz[:question]
    correct_answer = question[:answer].to_s.strip
    
    current_quiz[:attempts][user_id] = true
    
    if user_answer.downcase == correct_answer.downcase
      current_quiz[:answered] = true
      event.answer("🎉 @id#{user_id}, ВЕРНО! Ответ: #{question[:answer]}\n+10 очков!")
      award_points(chat_id, user_id, Settings::POINTS_PER_ANSWER)
      @active_quizzes.delete(chat_id)
      return true
    end
    
    false
  end
  
  # ========== ТУРНИРНЫЙ РЕЖИМ (без блокирующего sleep) ==========
  
  def start_tournament(event, rounds = 5)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    
    if @tournaments[chat_id]
      event.answer("❌ В этом чате уже идет турнир!")
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
      "👉 Организатор напишите '/tournament_start' когда все будут готовы"
    )
  end
  
  def join_tournament(event)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    
    tournament = @tournaments[chat_id]
    
    unless tournament
      event.answer("❌ Нет активного турнира")
      return
    end
    
    if tournament[:status] != :registration
      event.answer("❌ Регистрация закрыта!")
      return
    end
    
    if tournament[:players][user_id]
      event.answer("⚠ Вы уже в списке!")
    else
      tournament[:players][user_id] = { joined_at: Time.now }
      tournament[:scores][user_id] = 0
      event.answer("✅ @id#{user_id} присоединился! Участников: #{tournament[:players].size}")
    end
  end
  
  def begin_tournament_rounds(event)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    
    tournament = @tournaments[chat_id]
    return unless tournament
    
    if tournament[:creator_id] != user_id
      event.answer("❌ Только организатор может начать!")
      return
    end
    
    if tournament[:players].empty?
      event.answer("❌ Нет участников!")
      return
    end
    
    tournament[:status] = :in_progress
    tournament[:questions] = (0...tournament[:total_rounds]).map { @question_manager.get_random_question }
    
    event.answer("🎮 ТУРНИР НАЧИНАЕТСЯ!\n👥 Участников: #{tournament[:players].size}")
    
    # Запускаем первый раунд в отдельном потоке
    Thread.new do
      sleep(3)
      start_next_round(chat_id, event.api)
    end
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
    tournament[:round_start_time] = Time.now
    
    api.messages_send(
      peer_id: chat_id,
      message: "📌 Раунд #{tournament[:current_round]}/#{tournament[:total_rounds]}\n\n❓ #{question[:question]}\n\n⏱ 30 секунд на ответ!",
      random_id: rand(1000000..9999999)
    )
    
    # Таймер в отдельном потоке
    Thread.new do
      sleep(30)
      if @tournaments[chat_id] && @tournaments[chat_id][:status] == :in_progress && @tournaments[chat_id][:current_round] == tournament[:current_round]
        process_tournament_round(chat_id, api)
      end
    end
  end
  
  def process_tournament_round(chat_id, api)
    tournament = @tournaments[chat_id]
    return unless tournament
    
    question = tournament[:current_question]
    correct_answer = question[:answer].to_s.strip
    
    puts "🔍 ОТЛАДКА ТУРНИРА:"
    puts "   Ответы игроков: #{tournament[:round_answers].inspect}"
    
    round_results = "📊 Результаты раунда #{tournament[:current_round]}:\n\n"
    round_results += "✅ Правильный ответ: #{correct_answer}\n\n"
    
    tournament[:players].each do |user_id, _|
      player_answer = tournament[:round_answers][user_id]
      
      is_correct = false
      if player_answer
        is_correct = (player_answer.to_s.downcase.strip == correct_answer.downcase.strip)
      end
      
      if is_correct
        tournament[:scores][user_id] += Settings::POINTS_PER_ANSWER
        round_results += "✓ @id#{user_id}: +#{Settings::POINTS_PER_ANSWER} очков\n"
      else
        round_results += "✗ @id#{user_id}: 0 очков\n"
      end
    end
    
    round_results += "\n🏆 Текущий счет:\n"
    tournament[:scores].sort_by { |_, s| -s }.each_with_index do |(uid, s), i|
      round_results += "#{i+1}. @id#{uid}: #{s} очков\n"
    end
    
    api.messages_send(peer_id: chat_id, message: round_results, random_id: rand(1000000..9999999))
    
    Thread.new do
      sleep(5)
      start_next_round(chat_id, api)
    end
  end
  
    def handle_tournament_answer(event)
    chat_id = event.message.peer_id
    user_id = event.message.from_id
    user_answer = event.message.text.to_s.strip
    
    tournament = @tournaments[chat_id]
    return false unless tournament && tournament[:status] == :in_progress
    return false unless tournament[:players][user_id]
    return false if tournament[:round_answered]
    return false if tournament[:round_answers][user_id]
    
    tournament[:round_answers][user_id] = user_answer
    
    correct_answer = tournament[:current_question][:answer].to_s.strip
    
    if user_answer.downcase.strip == correct_answer.downcase.strip
      tournament[:round_answered] = true
      # Никакого сообщения! Просто сохраняем, что ответ правильный
    end
    
    true
  end
  
  def finish_tournament(chat_id, api)
    tournament = @tournaments.delete(chat_id)
    return unless tournament
    
    $db.transaction do
      $db[chat_id] ||= {}
      tournament[:scores].each do |uid, score|
        $db[chat_id][uid] ||= 0
        $db[chat_id][uid] += score
      end
    end
    
    message = "🏆 ТУРНИР ЗАВЕРШЕН! 🏆\n\n🥇 Итоги:\n\n"
    medals = ['🥇', '🥈', '🥉']
    tournament[:scores].sort_by { |_, s| -s }.each_with_index do |(uid, s), i|
      medal = i < 3 ? medals[i] : "#{i+1}."
      message += "#{medal} @id#{uid}: #{s} очков\n"
    end
    message += "\n🎊 Поздравляем!"
    api.messages_send(peer_id: chat_id, message: message, random_id: rand(1000000..9999999))
  end
  
  # ========== РЕЙТИНГ И СТАТИСТИКА ==========
  
  def show_rating(event)
    chat_id = event.message.peer_id
    rating = "🏆 РЕЙТИНГ\n\n"
    $db.transaction(true) do
      data = $db.fetch(chat_id, {})
      if data.empty?
        rating += "Пока пусто"
      else
        data.sort_by { |_, s| -s }.first(10).each_with_index do |(uid, s), i|
          rating += "#{i+1}. @id#{uid}: #{s} очков\n"
        end
      end
    end
    event.answer(rating)
  end
  
  def show_themes(event)
    themes = @question_manager.get_all_themes
    msg = "📚 Темы:\n"
    themes.each { |t| msg += "• #{t}\n" }
    event.answer(msg)
  end
  
  def show_stats(event)
    chat_id = event.message.peer_id
    $db.transaction(true) do
      players = $db.fetch(chat_id, {}).size
      event.answer("📊 Статистика\n📝 Вопросов: #{@question_manager.questions_count}\n👥 Игроков: #{players}")
    end
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