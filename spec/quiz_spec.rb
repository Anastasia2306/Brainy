# frozen_string_literal: true

require_relative '../quiz'
require 'json'
require 'pstore'

RSpec.describe Quiz do
  let(:quiz) { Quiz.new }

  before do
    stub_const('Settings::POINTS_PER_ANSWER', 10)
    stub_const('Settings::RATING_LIMIT', 10)
    stub_const('Settings::ANSWER_TIMEOUT', 30)

    # Создаём тестовую базу данных
    $db = PStore.new('spec/test_quiz.pstore')

    File.write('spec/test_questions.json', JSON.pretty_generate([
                                                                  { id: 1, theme: 'История',
                                                                    question: 'Год крещения Руси?', answer: '988', difficulty: 'средняя' },
                                                                  { id: 2, theme: 'Наука',
                                                                    question: 'Химический элемент Au?', answer: 'Золото', difficulty: 'легкая' },
                                                                  { id: 3, theme: 'География',
                                                                    question: 'Столица Японии?', answer: 'Токио', difficulty: 'легкая' }
                                                                ]))

    # Подменяем менеджер вопросов на тестовый
    quiz.instance_variable_set(:@question_manager, QuestionManager.new('spec/test_questions.json'))
  end

  after do
    FileUtils.rm_f('spec/test_questions.json')
    FileUtils.rm_f('spec/test_quiz.pstore')
  end

  let(:event) do
    double('Event',
           message: double('Message',
                           peer_id: 2_000_000_001,
                           from_id: 629_175_124,
                           text: 'ответ пользователя'),
           api: double('Api', messages_send: nil))
  end

  describe '#welcome_message' do
    it 'отправляет приветственное сообщение' do
      expect(event).to receive(:answer).with(/Привет! Я бот/)
      quiz.welcome_message(event)
    end
  end

  describe '#start_fast_quiz' do
    before do
      allow(event).to receive(:answer)
    end

    it 'запускает быструю викторину' do
      expect(event).to receive(:answer).with(/🎯 БЫСТРАЯ ВИКТОРИНА/)
      quiz.start_fast_quiz(event)
    end

    it 'не запускает вторую викторину' do
      quiz.start_fast_quiz(event)
      expect(event).to receive(:answer).with(/уже идет викторина/)
      quiz.start_fast_quiz(event)
    end

    it 'запускает викторину по теме' do
      expect(event).to receive(:answer).with(/📚 Тема: История/)
      quiz.start_fast_quiz(event, 'История')
    end

    it 'сообщает если тема не найдена' do
      expect(event).to receive(:answer).with(/Вопросы не найдены/)
      quiz.start_fast_quiz(event, 'Несуществующая')
    end
  end

  describe '#handle_answer' do
    before do
      allow(event.message).to receive(:peer_id).and_return(2_000_000_001)
      allow(event.message).to receive(:from_id).and_return(629_175_124)
      allow(event).to receive(:answer)
    end

    it 'возвращает false если нет активной викторины' do
      allow(event.message).to receive(:text).and_return('988')
      expect(quiz.handle_answer(event)).to be false
    end

    it 'засчитывает правильный ответ' do
      quiz.instance_variable_set(:@active_quizzes, {
                                   2_000_000_001 => {
                                     question: { id: 1, theme: 'История', question: 'Год?', answer: '988' },
                                     attempts: {},
                                     answered: false
                                   }
                                 })
      allow(event.message).to receive(:text).and_return('988')
      expect(event).to receive(:answer).with(/ВЕРНО/)
      quiz.handle_answer(event)
    end

    it 'не засчитывает повторный ответ' do
      quiz.instance_variable_set(:@active_quizzes, {
                                   2_000_000_001 => {
                                     question: { id: 1, theme: 'История', question: 'Год?', answer: '988' },
                                     attempts: { 629_175_124 => true },
                                     answered: false
                                   }
                                 })
      allow(event.message).to receive(:text).and_return('988')
      expect(quiz.handle_answer(event)).to be false
    end
  end

  describe '#start_tournament' do
    before do
      allow(event).to receive(:answer)
    end

    it 'создаёт турнир' do
      expect(event).to receive(:answer).with(/ТУРНИР НАЧИНАЕТСЯ/)
      quiz.start_tournament(event)
    end

    it 'не создаёт второй турнир' do
      quiz.start_tournament(event)
      expect(event).to receive(:answer).with(/уже идет турнир/)
      quiz.start_tournament(event)
    end
  end

  describe '#join_tournament' do
    before do
      allow(event).to receive(:answer)
    end

    it 'сообщает если нет активного турнира' do
      expect(event).to receive(:answer).with(/Нет активного турнира/)
      quiz.join_tournament(event)
    end

    it 'добавляет игрока в турнир' do
      quiz.start_tournament(event)
      expect(event).to receive(:answer).with(/присоединился/)
      quiz.join_tournament(event)
    end
  end

  describe '#show_rating' do
    it 'показывает пустой рейтинг' do
      allow(event).to receive(:answer)
      allow(event.message).to receive(:peer_id).and_return(2_000_000_001)
      expect(event).to receive(:answer).with(/Пока пусто/)
      quiz.show_rating(event)
    end
  end

  describe '#show_themes' do
    it 'показывает список тем' do
      allow(event).to receive(:answer)
      allow(event.message).to receive(:peer_id)
      expect(event).to receive(:answer).with(/📚 Темы:/)
      quiz.show_themes(event)
    end
  end

  describe '#show_stats' do
    it 'показывает статистику' do
      allow(event).to receive(:answer)
      allow(event.message).to receive(:peer_id).and_return(2_000_000_001)
      expect(event).to receive(:answer).with(/📊 Статистика/)
      quiz.show_stats(event)
    end
  end
end
