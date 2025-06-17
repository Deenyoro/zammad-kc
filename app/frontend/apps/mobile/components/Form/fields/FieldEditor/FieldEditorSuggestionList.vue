<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, toRef } from 'vue'

import useNavigateOptions from '#shared/components/Form/fields/FieldEditor/composables/useNavigateOptions.ts'
import type {
  MentionKnowledgeBaseItem,
  MentionTextItem,
  MentionType,
  MentionUserItem,
} from '#shared/components/Form/fields/FieldEditor/types.ts'
import { i18n } from '#shared/i18n.ts'

import type { SuggestionKeyDownProps } from '@tiptap/suggestion'

type PossibleItem = MentionUserItem | MentionKnowledgeBaseItem | MentionTextItem

interface Props {
  loading?: boolean
  query: string
  items: PossibleItem[]
  type: MentionType
  command: (item: PossibleItem) => void
}

const props = defineProps<Props>()

const isKnowledgeBaseItem = (item: unknown): item is MentionKnowledgeBaseItem => {
  return props.type === 'knowledge-base'
}

const isUserItem = (item: unknown): item is MentionUserItem => {
  return props.type === 'user'
}

const isTextItem = (item: unknown): item is MentionTextItem => {
  return props.type === 'text'
}

const { selectItem, selectedIndex, onKeyDown } = useNavigateOptions(toRef(props, 'items'), (item) =>
  props.command(item as MentionUserItem),
)

defineExpose({
  onKeyDown: (props: SuggestionKeyDownProps) => {
    return onKeyDown(props.event)
  },
})

const emptyMessage = computed(() => {
  if (props.loading) return i18n.t('Loading…')
  if (props.query) return i18n.t('No results found')
  if (props.type === 'knowledge-base') return i18n.t('Start typing to search in Knowledge Base…')
  if (props.type === 'text') return i18n.t('Start typing to search for text modules…')
  if (props.type === 'user') return i18n.t('Start typing to search for users…')

  return i18n.t('Start typing to search…')
})
</script>

<template>
  <ul
    class="max-h-64 overflow-auto rounded bg-gray-300 text-white z-10"
    :data-test-id="`mention-${type}`"
    role="listbox"
  >
    <li
      v-for="(item, index) in items"
      :id="`mention-${index}`"
      :key="item.id"
      class="cursor-pointer px-6 py-2 hover:bg-gray-400"
      :class="{ 'bg-gray-400': selectedIndex === index }"
      role="option"
      :aria-selected="selectedIndex === index"
      tabindex="0"
      @click="selectItem(index)"
      @keydown.space.prevent="selectItem(index)"
    >
      <template v-if="isKnowledgeBaseItem(item)">
        <div class="text-sm">
          {{ item.categoryTreeTranslation.map((c) => c.title).join(' ') }}
        </div>
        <div>{{ item.title }}</div>
      </template>
      <div v-else-if="isTextItem(item)" class="flex flex-row items-center gap-2">
        <div>
          {{ item.name }}
        </div>
        <div v-if="item.keywords" class="border-gray-150 rounded border border-solid px-1 text-sm">
          {{ item.keywords }}
        </div>
      </div>
      <template v-else-if="isUserItem(item)">
        {{ item.fullname }}
        {{ item.email ? `<${item.email}>` : '' }}
      </template>
    </li>
    <li v-if="!items.length" class="px-6 py-1 text-white">
      {{ emptyMessage }}
    </li>
  </ul>
</template>
