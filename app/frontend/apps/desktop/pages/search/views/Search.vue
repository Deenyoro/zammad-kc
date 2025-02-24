<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import LayoutMain from '#desktop/components/layout/LayoutMain.vue'
// import LayoutTaskbarTabContent from '#desktop/components/layout/LayoutTaskbarTabContent.vue'

interface Props {
  searchTerm?: string
}
defineProps<Props>()
</script>

<template>
  <!--  :TODO taskbar item-->
  <!--  <LayoutTaskbarTabContent>-->
  <!--    <div>Search</div>-->
  <!--  </LayoutTaskbarTabContent>-->
  <LayoutMain>
    <div class="bg-white">Search🦉</div>
    <pre>{{ searchTerm }}</pre>
  </LayoutMain>
</template>
