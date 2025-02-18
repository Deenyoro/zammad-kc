<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import AddMenu from '#desktop/components/layout/LayoutSidebar/LeftSidebar/MenuContainer/AddMenu/AddMenu.vue'
import SettingMenu from '#desktop/components/layout/LayoutSidebar/LeftSidebar/MenuContainer/AdminMenu/AdminMenu.vue'
import { useCollapsedState } from '#desktop/components/layout/LayoutSidebar/LeftSidebar/useCollapsedState.ts'

const { collapsedState } = useCollapsedState()
</script>

<template>
  <div
    role="list"
    class="flex items-center gap-4 rounded-xl bg-gray-700 p-4 empty:hidden"
    :class="{ 'flex-col bg-transparent': collapsedState }"
  >
    <SettingMenu role="listitem" />
    <AddMenu role="listitem" />
  </div>
</template>
