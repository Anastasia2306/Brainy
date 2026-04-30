# frozen_string_literal: true

module Keyboards
  MAIN = {
    one_time: false,
    buttons: [
      [{ action: { type: 'text', label: '🎮 Викторина' }, color: 'primary' },
       { action: { type: 'text', label: '📚 Темы' }, color: 'default' }],
      [{ action: { type: 'text', label: '🏆 Турнир' }, color: 'positive' },
       { action: { type: 'text', label: '⭐ Рейтинг' }, color: 'default' }],
      [{ action: { type: 'text', label: '📊 Статистика' }, color: 'default' },
       { action: { type: 'text', label: '❓ Помощь' }, color: 'default' }]
    ]
  }.freeze

  TOURNAMENT = {
    one_time: false,
    buttons: [
      [{ action: { type: 'text', label: '➕ Присоединиться' }, color: 'positive' }],
      [{ action: { type: 'text', label: '🚀 Начать турнир' }, color: 'primary' }],
      [{ action: { type: 'text', label: '◀ Назад' }, color: 'default' }]
    ]
  }.freeze
end