<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
export interface Props {
  label: string
  alternativeBackground?: boolean
}

const props = defineProps<Props>()
</script>

<template>
  <div
    role="region"
    :aria-label="$t(label)"
    class="rounded-lg p-3"
    :class="{
      'bg-blue-200 dark:bg-gray-500': !props.alternativeBackground,
      'bg-blue-200 dark:bg-gray-700': props.alternativeBackground,
    }"
  >
    <slot />
  </div>
</template>
