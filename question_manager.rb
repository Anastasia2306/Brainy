require 'json'

class QuestionManager
  attr_reader :questions
  
  def initialize(questions_file = 'data/questions.json')
    @questions_file = questions_file
    load_questions
  end
  
  def load_questions
    begin
      file_content = File.read(@questions_file)
      @questions = JSON.parse(file_content, symbolize_names: true)
    rescue Errno::ENOENT
      puts "Файл с вопросами не найден: #{@questions_file}"
      @questions = []
    rescue JSON::ParserError
      puts "Ошибка парсинга JSON файла: #{@questions_file}"
      @questions = []
    end
  end
  
  def get_random_question(theme = nil)
    filtered = theme ? @questions.select { |q| q[:theme].downcase == theme.downcase } : @questions
    filtered.sample
  end
  
  def get_question_by_id(id)
    @questions.find { |q| q[:id] == id }
  end
  
  def get_all_themes
    @questions.map { |q| q[:theme] }.uniq.sort
  end
  
  def questions_count
    @questions.size
  end
  
  def questions_by_theme(theme)
    @questions.select { |q| q[:theme].downcase == theme.downcase }
  end
end