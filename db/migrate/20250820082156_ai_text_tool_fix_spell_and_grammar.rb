# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AITextToolFixSpellAndGrammar < ActiveRecord::Migration[7.2]
  def change
    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    create_ai_text_tool
    migrate_ai_assistance_text_tools_fixed_instructions
  end

  private

  def create_ai_text_tool
    AI::TextTool.create_if_not_exists(
      name:          'Fix spelling and grammar',
      instruction:   'You are a text correction AI assistant.

You are given a text, most likely in HTML format.

Your task is to correct:
- spelling
- grammar
- punctuation
- and sentence-structure errors.

You have to follow these rules:
- Detect the input language and make sure the corrected text is using the same language.
- Correct only the text content, neither the HTML tags nor the given structure.
- Preserve all HTML tags and formatting exactly as in the input.',
      note:          'This Writing Assistant Tool corrects spelling and grammar errors in the text.',
      active:        true,
      updated_by_id: 1,
      created_by_id: 1
    )
  end

  def migrate_ai_assistance_text_tools_fixed_instructions
    setting = Setting.find_by(name: 'ai_assistance_text_tools_fixed_instructions')
    return if !setting

    new_instructions = 'Do not provide any explanations, code fences or additional text. Output only the corrected text.'

    setting.update!(
      state_current: { value: new_instructions },
      state_initial: { value: new_instructions },
    )
  end
end
