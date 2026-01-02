<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, ref } from 'vue'

import { isInlineAttributeEditable } from '#shared/components/ObjectAttributes/utils.ts'

import type { ObjectAttributeRichtext } from './attributeRichtextTypes.ts'
import type { ObjectAttributeProps } from '../../types.ts'

const props = defineProps<ObjectAttributeProps<ObjectAttributeRichtext, string>>()

const modelValue = ref(props.value)

const handleReset = () => {
  modelValue.value = props.value
}

const enableInlineEdit = computed(
  () =>
    props.mode === 'view' && isInlineAttributeEditable(props.attribute.name, props.inlineEditable),
)
</script>

<template>
  <FormKit
    v-if="enableInlineEdit"
    :id="attribute.id"
    v-model="modelValue"
    :name="attribute.display"
    :classes="{
      outer: 'w-full',
      inner: 'dark:bg-transparent bg-transparent outline-0!',
      input: 'min-h-7!',
    }"
    type="editor"
    :meta="{
      footer: {
        maxlength: props.attribute?.dataOption?.maxlength,
        disabled: true,
      },
    }"
    :label-sr-only="true"
    :label="attribute.display"
    :reset="handleReset"
    :inline="true"
    extension-set="basic"
  />
  <!-- eslint-disable vue/no-v-html -->
  <div v-else v-html="value" />
</template>
