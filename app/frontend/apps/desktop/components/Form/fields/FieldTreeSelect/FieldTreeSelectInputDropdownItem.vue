<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, useTemplateRef } from 'vue'

import type {
  FlatSelectOption,
  MatchedFlatSelectOption,
} from '#shared/components/Form/fields/FieldTreeSelect/types.ts'
import { i18n } from '#shared/i18n.ts'
import { useLocaleStore } from '#shared/stores/locale.ts'

import CommonDivider from '#desktop/components/CommonDivider/CommonDivider.vue'

const props = defineProps<{
  option: FlatSelectOption | MatchedFlatSelectOption
  selected?: boolean
  multiple?: boolean
  noLabelTranslate?: boolean
  filter?: string
  noSelectionIndicator?: boolean
  index?: number
  hasTopButton?: boolean
}>()

const emit = defineEmits<{
  select: [option: FlatSelectOption]
  next: [{ option: FlatSelectOption; noFocus?: boolean }]
}>()

const locale = useLocaleStore()

const select = (option: FlatSelectOption) => {
  if (props.option.disabled) return

  emit('select', option)
}

const label = computed(() => {
  const { option } = props

  if (props.noLabelTranslate) return option.label || option.value.toString()

  return i18n.t(option.label, ...(option.labelPlaceholder || [])) || option.value.toString()
})

const goToNextPage = (option: FlatSelectOption, noFocus?: boolean) => {
  emit('next', { option, noFocus })
}

const optionElement = useTemplateRef('option-button')

const handleClickOnNext = (option: FlatSelectOption | MatchedFlatSelectOption) => {
  if (option.disabled) return optionElement.value?.click()
  goToNextPage(option)
}

const handleNextPageOrSelect = () =>
  props.option.disabled ? goToNextPage(props.option, true) : select(props.option)
</script>

<template>
  <div
    role="option"
    :aria-selected="selected"
    class="flex group h-9 cursor-pointer items-center self-stretch text-sm text-black outline-hidden dark:text-white"
    :class="{
      'group hover:bg-green-200 dark:hover:bg-gray-600 dark:active:bg-gray-700 active:bg-green-300 rtl:pr-2.5 ltr:pl-2.5 has-focus-visible:shadow-[inset_0_0_0_1px_var(--color-blue-800)] ':
        option.disabled,
      'px-0!': !option.hasChildren,
    }"
  >
    <div
      ref="option-button"
      role="button"
      tabindex="0"
      class="size-full flex items-center gap-1.5"
      :class="{
        'group/button hover:bg-blue-600 active:bg-blue-800 dark:active:bg-blue-800  dark:hover:bg-blue-900 rtl:pr-2.5 ltr:pl-2.5 focus-visible-app-default -outline-offset-1!':
          !option.disabled,
        'hover:text-black  dark:hover:text-white outline-none': option.disabled,
        'rounded-tl-lg!': !hasTopButton && index === 0,
      }"
      :aria-description="option.disabled ? $t('This item expands to show more options') : undefined"
      :data-value="option.value"
      @click="handleNextPageOrSelect"
      @keydown.space.prevent="handleNextPageOrSelect"
      @keydown.enter.prevent="handleNextPageOrSelect"
    >
      <CommonIcon
        v-if="multiple && !noSelectionIndicator"
        size="xs"
        decorative
        :name="selected ? 'check-square' : 'square'"
        class="m-0.5 shrink-0 fill-gray-100 group-hover/button:fill-black group-active/button:fill-white dark:fill-neutral-400 dark:group-hover/button:fill-white"
        :class="{
          'opacity-30 group-hover/button:text-gray-100! group-hover/button:dark:text-neutral-400!':
            option.disabled,
        }"
      />
      <!--  We need to check if disabled is here the way to go or remove the checkbox entirely    -->

      <CommonIcon
        v-else-if="!noSelectionIndicator"
        class="shrink-0 fill-gray-100 group-hover:fill-black dark:fill-neutral-400 group-active/button:fill-white dark:group-hover:fill-white"
        :class="{
          invisible: !selected,
        }"
        decorative
        size="tiny"
        name="check2"
      />
      <CommonIcon
        v-if="option.icon"
        :name="option.icon"
        size="tiny"
        decorative
        class="shrink-0 fill-gray-100 group-hover/button:fill-black dark:fill-neutral-400 dark:group-hover:fill-white"
      />
      <!--      eslint-disable vue/no-v-html -->
      <span
        v-if="filter"
        v-tooltip="label"
        :class="{
          'pointer-events-none text-stone-200 dark:text-neutral-500': option.disabled,
        }"
        class="grow truncate dark:group-hover/button:text-white group-hover/button:text-black group-active/button:text-white"
        v-html="(option as MatchedFlatSelectOption).matchedPath"
      />
      <span
        v-else
        v-tooltip="label"
        class="grow truncate dark:group-hover/button:text-white group-hover/button:text-black group-active/button:text-white"
      >
        {{ label }}
      </span>

      <CommonDivider
        v-if="!option.disabled && option.hasChildren"
        orientation="vertical"
        class="h-[70%]! group-hover:invisible"
        variant="stone"
      />
    </div>
    <!--  eslint-disable vuejs-accessibility/no-static-element-interactions  -->
    <div
      v-if="option.hasChildren && !filter"
      class="shrink-0 flex items-center justify-center gap-x-2.5 p-2.5 h-full"
      :class="{
        'hover:bg-green-200 focus-visible-app-default -outline-offset-1! dark:hover:bg-gray-600 active:bg-green-300 dark:active:bg-gray-700':
          !option.disabled,
        'rounded-tr-lg': !hasTopButton && index === 0,
      }"
      :aria-label="$t('Has submenu')"
      :role="option.disabled ? 'presentation' : 'button'"
      :tabindex="option.disabled ? -1 : 0"
      @click="handleClickOnNext(option)"
      @keydown.enter.prevent="handleClickOnNext(option)"
      @keydown.space.prevent="handleClickOnNext(option)"
    >
      <CommonIcon
        :class="{
          'dark:group-hover:fill-white group-hover:fill-black': option.disabled,
        }"
        class="shrink-0 fill-stone-200"
        :name="locale.localeData?.dir === 'rtl' ? 'chevron-left' : 'chevron-right'"
        size="xs"
        decorative
      />
    </div>
  </div>
</template>
