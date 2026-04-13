<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { shallowRef } from 'vue'

import DragAndDropBulkEntityCard from './DragAndDropBulkEntityCard.vue'
import { DragAndDropBulkEntityType } from './types.ts'

defineProps<{
  isActive: boolean
}>()

const isInsideGroup = shallowRef(false)

const goInsideGroup = (groupId: ID) => {
  isInsideGroup.value = true
  console.log('go inside group with id', groupId)
  // :TODO load group details and show them in the drawer
}
</script>

<template>
  <div class="w-full">
    <transition
      appear
      mode="out-in"
      enter-active-class="transition duration-200"
      leave-active-class="transition duration-200"
      enter-from-class="opacity-0 translate-y-full"
      leave-to-class="opacity-0 translate-y-full"
    >
      <header v-if="!isActive" class="flex h-52 w-full items-center justify-center py-3">
        <DragAndDropBulkEntityCard
          circle
          :entity-type="DragAndDropBulkEntityType.Ticket"
          :label="$t('Assign tickets')"
        />
      </header>

      <header
        v-else
        class="grid w-full grid-rows-[repeat(2,auto)] justify-center gap-3 bg-blue-200 py-3 dark:bg-gray-500"
      >
        <CommonLabel class="block! text-center" tag="h3">{{ $t('Assign tickets') }}</CommonLabel>

        <ul class="flex flex-row gap-7">
          <!-- TODO: WIP: horizontal scrolling icons, a lot is still missing: -->
          <!-- TODO: positioning, styling, logic when to show, ...  -->
          <!-- TODO: placeholder icons: need SVG files for arrow-right, arrow-left in `app/frontend/apps/desktop/initializer/assets` -->
          <span class="absolute inset-y-20 ltr:left-4 rtl:right-4">
            <CommonIcon
              class="rounded-md text-black dark:bg-blue-900 dark:text-white"
              name="arrow-bar-left"
            />
          </span>
          <span class="absolute inset-y-20 ltr:right-4 rtl:left-4">
            <CommonIcon
              class="rounded-md text-black dark:bg-blue-900 dark:text-white"
              name="arrow-bar-right"
            />
          </span>
          <li>
            <DragAndDropBulkEntityCard
              :entity-type="DragAndDropBulkEntityType.Ticket"
              label="Nicole"
              @go-inside-group="goInsideGroup"
            />
          </li>
        </ul>
      </header>
    </transition>
  </div>
</template>
