require_relative '../question_manager'

RSpec.describe QuestionManager do
  let(:test_file) { 'spec/test_questions.json' }
  let(:questions) do
    [
      { id: 1, theme: 'История', question: 'Вопрос 1', answer: 'Ответ 1', difficulty: 'легкая' },
      { id: 2, theme: 'Наука', question: 'Вопрос 2', answer: 'Ответ 2', difficulty: 'средняя' }
    ]
  end

  before do
    File.write(test_file, JSON.pretty_generate(questions))
  end

  after do
    File.delete(test_file) if File.exist?(test_file)
  end

  describe '#initialize' do
    it 'загружает вопросы из файла' do
      manager = QuestionManager.new(test_file)
      expect(manager.questions_count).to eq(2)
    end
  end

  describe '#get_random_question' do
    it 'возвращает случайный вопрос' do
      manager = QuestionManager.new(test_file)
      question = manager.get_random_question
      expect(question).to be_a(Hash)
      expect(question[:question]).to match(/Вопрос/)
    end

    it 'фильтрует по теме' do
      manager = QuestionManager.new(test_file)
      question = manager.get_random_question('Наука')
      expect(question[:theme]).to eq('Наука')
    end
  end

  describe '#get_all_themes' do
    it 'возвращает список уникальных тем' do
      manager = QuestionManager.new(test_file)
      expect(manager.get_all_themes).to eq(['История', 'Наука'])
    end
  end

  describe '#questions_count' do
    it 'возвращает количество вопросов' do
      manager = QuestionManager.new(test_file)
      expect(manager.questions_count).to eq(2)
    end
  end

  describe '#questions_by_theme' do
    it 'возвращает вопросы по теме' do
      manager = QuestionManager.new(test_file)
      questions = manager.questions_by_theme('История')
      expect(questions.size).to eq(1)
      expect(questions.first[:theme]).to eq('История')
    end
  end
end