<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import CommonSkeleton from '#desktop/components/CommonSkeleton/CommonSkeleton.vue'
</script>

<template>
  <div class="flex flex-col gap-4">
    <CommonSkeleton class="h-4 w-1/3" alternative-background />
    <div class="flex items-center h-9 gap-2 mb-2">
      <CommonSkeleton
        :style="{ 'animation-delay': `${0.1}s` }"
        class="h-5 w-5 -translate-y-2"
        rounded
      />
      <div class="grow flex flex-col gap-1">
        <CommonSkeleton
          :style="{ 'animation-delay': `${0.1}s` }"
          class="h-4 w-4/5"
          alternative-background
        />
        <CommonSkeleton
          :style="{ 'animation-delay': `${0.1}s` }"
          class="h-4 w-1/3"
          alternative-background
        />
      </div>
    </div>
    <div class="flex items-center h-9 gap-2 mb-2">
      <CommonSkeleton
        :style="{ 'animation-delay': `${0.2}s` }"
        class="h-5 w-5 -translate-y-2"
        rounded
        alternative-background
      />
      <div class="grow flex flex-col gap-1">
        <CommonSkeleton
          :style="{ 'animation-delay': `${0.2}s` }"
          class="h-4 w-3/5"
          alternative-background
        />
        <CommonSkeleton
          :style="{ 'animation-delay': `${0.2}s` }"
          class="h-4 w-1/3"
          alternative-background
        />
      </div>
    </div>
    <div class="flex items-center h-9 gap-2">
      <CommonSkeleton
        :style="{ 'animation-delay': `${0.3}s` }"
        class="h-5 w-5 -translate-y-2"
        rounded
        alternative-background
      />
      <div class="grow flex flex-col gap-1">
        <CommonSkeleton
          :style="{ 'animation-delay': `${0.3}s` }"
          class="h-4 w-full"
          alternative-background
        />
        <CommonSkeleton
          :style="{ 'animation-delay': `${0.3}s` }"
          class="h-4 w-1/3"
          alternative-background
        />
      </div>
    </div>
    <CommonSkeleton class="self-end h-6 w-1/5" />
  </div>
</template>
