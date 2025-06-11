<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import type { ObjectAttributeRichtext } from './attributeRichtextTypes.ts'
import type { ObjectAttributeProps } from '../../types.ts'

defineProps<ObjectAttributeProps<ObjectAttributeRichtext, string>>()
</script>

<template>
  <!-- eslint-disable vue/no-v-html -->
  <div v-html="value" />
</template>
