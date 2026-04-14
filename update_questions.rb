require 'json'
require 'net/http'
require 'uri'
require 'cgi'
require 'set'

class QuestionsUpdater
  # URL для Open Trivia Database
  # Можно менять параметры:
  # amount=50 — количество вопросов (максимум 50)
  # category=9 — категория (9=General Knowledge, 18=Computers, 23=History и т.д.)
  # difficulty=medium — сложность (easy, medium, hard)
  # type=multiple — только вопросы с вариантами ответов
  API_URL = 'https://opentdb.com/api.php?amount=50&type=multiple'

  def initialize(file_path = 'data/questions.json')
    @file_path = file_path
    @stats = { added: 0, skipped: 0 }
  end

  # Основной метод — скачать и сохранить новые вопросы
  def update
    puts "Скачиваю вопросы из Open Trivia Database..."

    new_questions = fetch_questions

    if new_questions.empty?
      puts "Не получено ни одного вопроса"
      return
    end

    puts "Получено #{new_questions.size} вопросов"

    # Загружаем существующие вопросы
    existing = load_existing
    puts "В базе уже есть #{existing.size} вопросов"

    # Объединяем, избегая дубликатов по тексту вопроса
    merged = merge_questions(existing, new_questions)

    # Сохраняем обратно в JSON
    save_questions(merged)

    puts " Сохранено!"
    puts "    Добавлено новых: #{@stats[:added]}"
    puts "    Пропущено (дубликаты): #{@stats[:skipped]}"
    puts "    Всего вопросов в базе: #{merged.size}"
  end

  private

  def fetch_questions
    puts "   Отправляю запрос к OpenTDB..."
    uri = URI(API_URL)
    response = Net::HTTP.get(uri)
    data = JSON.parse(response, symbolize_names: true)

    if data[:response_code] != 0
      puts "    OpenTDB вернул ошибку (код: #{data[:response_code]})"
      return []
    end

    # Преобразуем формат OpenTDB в формат нашего бота
    new_questions = []

    data[:results].each do |q|
      new_questions << {
        theme: q[:category],
        question: CGI.unescapeHTML(q[:question]),
        answer: CGI.unescapeHTML(q[:correct_answer]),
        difficulty: q[:difficulty]
      }
    end

    puts "   Скачано #{new_questions.size} вопросов"
    new_questions

  rescue => e
    puts "   Ошибка при скачивании: #{e.message}"
    []
  end

  def load_existing
    return [] unless File.exist?(@file_path)

    file_content = File.read(@file_path)
    JSON.parse(file_content, symbolize_names: true)
  rescue JSON::ParserError => e
    puts "   Ошибка чтения JSON: #{e.message}. Начинаем с пустой базы."
    []
  end

  def merge_questions(existing, new)
    # Создаём Set с текстами существующих вопросов для быстрой проверки на дубликаты
    # Приводим к нижнему регистру и убираем лишние пробелы для точного сравнения
    existing_texts = existing.map { |q| normalize_question(q[:question]) }.to_set

    # Определяем максимальный ID для новых вопросов
    max_id = existing.map { |q| q[:id] }.compact.max || 0

    new.each do |question|
      normalized_text = normalize_question(question[:question])

      if existing_texts.include?(normalized_text)
        @stats[:skipped] += 1
        next # пропускаем дубликат
      end

      # Присваиваем новый ID
      max_id += 1
      question[:id] = max_id

      existing << question
      existing_texts.add(normalized_text)
      @stats[:added] += 1
    end

    existing
  end

  def normalize_question(text)
    text.to_s
        .downcase
        .gsub(/\s+/, ' ')
        .strip
  end

  def save_questions(questions)
    # Сортируем по ID для удобства чтения файла
    sorted = questions.sort_by { |q| q[:id] }

    File.write(@file_path, JSON.pretty_generate(sorted))
  end
end

# ТОЧКА ВХОДА

if __FILE__ == $0
  puts "=" * 50
  puts "ОБНОВЛЕНИЕ БАЗЫ ВОПРОСОВ ИЗ Open Trivia Database"
  puts "=" * 50

  updater = QuestionsUpdater.new
  updater.update

  puts "\nГотово!"
end