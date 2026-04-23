require 'json'
require 'net/http'
require 'uri'
require 'cgi'
require 'set'

class QuestionsUpdater
  API_URL = 'https://opentdb.com/api.php?amount=50&type=multiple'
  TRANSLATE_API = 'https://api.mymemory.translated.net/get'
  
  THEME_TRANSLATIONS = {
    'General Knowledge' => 'Общие знания',
    'Entertainment: Books' => 'Литература',
    'Entertainment: Film' => 'Кино',
    'Entertainment: Music' => 'Музыка',
    'Entertainment: Television' => 'Телевидение',
    'Entertainment: Video Games' => 'Видеоигры',
    'Entertainment: Board Games' => 'Настольные игры',
    'Entertainment: Comics' => 'Комиксы',
    'Entertainment: Cartoon & Animations' => 'Мультфильмы',
    'Entertainment: Japanese Anime & Manga' => 'Аниме и манга',
    'Science & Nature' => 'Наука и природа',
    'Science: Computers' => 'Компьютеры',
    'Science: Mathematics' => 'Математика',
    'Science: Gadgets' => 'Гаджеты',
    'Mythology' => 'Мифология',
    'Sports' => 'Спорт',
    'Geography' => 'География',
    'History' => 'История',
    'Politics' => 'Политика',
    'Art' => 'Искусство',
    'Celebrities' => 'Знаменитости',
    'Animals' => 'Животные',
    'Vehicles' => 'Транспорт'
  }

  def initialize(file_path = 'data/questions.json')
    @file_path = file_path
    @stats = { added: 0, skipped: 0 }
    @translation_cache = {}  # Кеш переводов
  end

  def update
    puts "📥 Скачиваю вопросы..."
    new_questions = fetch_questions
    if new_questions.empty?
      puts "❌ Ничего не получено"
      return
    end
    puts "✅ Получено #{new_questions.size} вопросов"
    
    puts "🌐 Перевожу..."
    translated = translate_questions(new_questions)
    
    existing = load_existing
    puts "📁 В базе #{existing.size} вопросов"
    merged = merge_questions(existing, translated)
    save_questions(merged)
    puts "💾 Готово! ➕#{@stats[:added]} ⏭️#{@stats[:skipped]} 📊#{merged.size}"
  end

  private

  def fetch_questions
    uri = URI(API_URL)
    response = Net::HTTP.get(uri)
    data = JSON.parse(response, symbolize_names: true)
    data[:response_code] == 0 ? data[:results] : []
  rescue => e
    puts "❌ Ошибка: #{e.message}"
    []
  end

  def translate_text(text, source = 'en', target = 'ru')
    return text if text.nil? || text.empty?
    
    # Проверяем кеш
    cache_key = "#{text}:#{target}"
    return @translation_cache[cache_key] if @translation_cache[cache_key]
    
    uri = URI(TRANSLATE_API)
    params = { q: text, langpair: "#{source}|#{target}" }
    uri.query = URI.encode_www_form(params)
    
    response = Net::HTTP.get(uri)
    data = JSON.parse(response)
    
    translated = if data['responseStatus'] == 200
      data['responseData']['translatedText']
    else
      text
    end
    
    @translation_cache[cache_key] = translated
    translated
  rescue
    text
  end

  def translate_questions(questions)
    total = questions.size
    translated = []
    
    questions.each_with_index do |q, index|
      print "\r   🔄 #{index + 1}/#{total}" if (index % 5 == 0)
      
      theme = THEME_TRANSLATIONS[q[:category]] || q[:category]
      question_ru = translate_text(CGI.unescapeHTML(q[:question]))
      answer_ru = translate_text(CGI.unescapeHTML(q[:correct_answer]))
      
      translated << {
        theme: theme,
        question: question_ru,
        answer: answer_ru,
        difficulty: translate_difficulty(q[:difficulty])
      }
    end
    
    puts "\r   ✅ Переведено #{total} вопросов"
    translated
  end

  def translate_difficulty(diff)
    case diff
    when 'easy' then 'легкая'
    when 'medium' then 'средняя'
    when 'hard' then 'сложная'
    else 'средняя'
    end
  end

  def load_existing
    return [] unless File.exist?(@file_path)
    JSON.parse(File.read(@file_path), symbolize_names: true)
  rescue
    []
  end

  def merge_questions(existing, new)
    existing_texts = existing.map { |q| normalize_question(q[:question]) }.to_set
    max_id = existing.map { |q| q[:id] }.compact.max || 0
    
    new.each do |question|
      if existing_texts.include?(normalize_question(question[:question]))
        @stats[:skipped] += 1
        next
      end
      max_id += 1
      question[:id] = max_id
      existing << question
      existing_texts.add(normalize_question(question[:question]))
      @stats[:added] += 1
    end
    existing
  end

  def normalize_question(text)
    text.to_s.downcase.gsub(/\s+/, ' ').strip
  end

  def save_questions(questions)
    File.write(@file_path, JSON.pretty_generate(questions.sort_by { |q| q[:id] }))
  end
end

if __FILE__ == $0
  puts "=" * 50
  puts "🔄 БАЗА ВОПРОСОВ (с переводом)"
  puts "=" * 50
  QuestionsUpdater.new.update
  puts "✨ Готово!"
end