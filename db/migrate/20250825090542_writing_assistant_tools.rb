# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class WritingAssistantTools < ActiveRecord::Migration[7.2]
  def change
    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    rewrite_complex_section
    expand_draft
    summarize_section

    adjust_fixed_instructions
  end

  private

  def rewrite_complex_section
    AI::TextTool.create_if_not_exists(
      name:          'Rewrite complex section and make it easy to understand',
      instruction:   'You are an AI assistant that helps to simplify demanding texts.

You are given a text, most likely in HTML format.

Your task is to simplify the text to improve comprehension.

You have to follow these rules:
- Always preserve the original input language (do not translate).
- Simplify complex words and phrases to make them easier to understand.
- Keep about the same length as the original text.
- Restructuring is allowed, but preserving the main message and key facts is most important.
- Preserve all HTML tags (e.g. links, images) and formatting (e.g. bold, italic) whenever it makes sense.',
      note:          'This Writing Assistant Tool simplifies the selected text and improves comprehension.',
      active:        true,
      updated_by_id: 1,
      created_by_id: 1
    )
  end

  def expand_draft
    AI::TextTool.create_if_not_exists(
      name:          'Expand draft into well-written section',
      instruction:   'You are an AI assistant that helps expand existing draft text into a structured and comprehensible version of the text.

You are given a text, most likely in HTML format.

Your task is to formulate the existing draft text into a well-structured and comprehensible text.

Follow these rules:
- Always preserve the original input language (do not translate).
- Only reuse the existing ideas.
- It is absolutely forbidden to
  - add new facts, statistics, or claims not present in the original.
  - add new factual claims not in the original text.
  - reference external sources or studies.
  - add names of people, places, or organizations not mentioned.
- To improve writing quality, you are allowed to change the structure, flow, and clarity of the text.
  - Introduce HTML tags for headings, paragraphs, listings etc. to create a well-readable text.
  - Only use HTML tags, no markdown and no complete HTML document.
- Maintain the original meaning and tone throughout.
- The expanded output should be maximum 2–4 times longer than the draft. Do not exceed this range and do not make the output unnaturally long.
- Preserve all HTML tags (e.g. links, images) as in the input.',
      note:          'This Writing Assistant Tool transforms the draft into a fully formulated text.',
      active:        true,
      updated_by_id: 1,
      created_by_id: 1
    )
  end

  def summarize_section
    AI::TextTool.create_if_not_exists(
      name:          'Summarize section to about half its current size',
      instruction:   'You are an AI assistant summarizing texts.

You are given a text, most likely in HTML format.

Your task is to create a concise summary for the given text.

Follow these rules:
- Always preserve the original input language (do not translate).
- The summary should be about 50% of the original length (at least 40% shorter).
  - Sentences can be combined.
  - Remove unnecessary words, filler, repetition, and non-essential details.
- Preserve all key information, main arguments, and important details.
- Maintain the original tone, but change the structure of the text when needed.
- Preserve image and link HTML tags.',
      note:          'This Writing Assistant Tool creates a short summary of the selected text keeping the original meaning.',
      active:        true,
      updated_by_id: 1,
      created_by_id: 1
    )
  end

  def adjust_fixed_instructions
    setting = Setting.find_by(name: 'ai_assistance_text_tools_fixed_instructions')
    return if setting.nil?

    new_instructions = 'Do not provide any explanations, code fences or additional text. Output only the modified text.'

    setting.update!(
      state_current: { value: new_instructions },
      state_initial: { value: new_instructions },
    )
  end
end
