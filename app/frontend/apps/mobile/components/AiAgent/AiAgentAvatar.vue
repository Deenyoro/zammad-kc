<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

interface Props {
  size?: 'small' | 'medium' | 'large'
}

const props = withDefaults(defineProps<Props>(), {
  size: 'small',
})

const sizeClass = computed(() => {
  switch (props.size) {
    case 'small':
      return 'w-6 h-6'
    case 'medium':
      return 'w-8 h-8'
    case 'large':
      return 'w-10 h-10'
    default:
      return 'w-8 h-8'
  }
})
</script>

<template>
  <div :class="sizeClass" class="relative rounded-full p-0.5 bg-gradient-to-r from-blue to-pink">
    <div :aria-label="$t('AI Agent')" class="p-1 bg-gray-600/90 rounded-full">
      <CommonIcon class="text-blue w-full h-full" size="tiny" name="ai-agent" />
    </div>
  </div>
</template>
