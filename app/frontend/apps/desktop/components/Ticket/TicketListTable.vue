<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { storeToRefs } from 'pinia'

import ObjectAttributeContent from '#shared/components/ObjectAttributes/ObjectAttribute.vue'
import type { ObjectAttribute } from '#shared/entities/object-attributes/types/store.ts'
import type { TicketByList } from '#shared/entities/ticket/types.ts'
import { EnumObjectManagerObjects } from '#shared/graphql/types.ts'
import { getIdFromGraphQLId } from '#shared/graphql/utils.ts'
import { useApplicationStore } from '#shared/stores/application.ts'
import type { ObjectWithId } from '#shared/types/utils.ts'

import CommonAdvancedTable from '#desktop/components/CommonTable/CommonAdvancedTable.vue'
import CommonTableSkeleton from '#desktop/components/CommonTable/Skeleton/CommonTableSkeleton.vue'
import CommonTicketPriorityIndicatorIcon from '#desktop/components/CommonTicketPriorityIndicator/CommonTicketPriorityIndicatorIcon.vue'
import CommonTicketStateIndicatorIcon from '#desktop/components/CommonTicketStateIndicator/CommonTicketStateIndicatorIcon.vue'
import UserPopoverWithTrigger from '#desktop/components/User/UserPopoverWithTrigger.vue'

import { useListTable } from '../CommonTable/composables/useListTable.ts'

import { useTicketBulkEdit } from './TicketBulkEditFlyout/useTicketBulkEdit.ts'

import type { ListTableEmits, ListTableProps } from '../CommonTable/types.ts'

const props = defineProps<ListTableProps<TicketByList>>()

const emit = defineEmits<ListTableEmits>()

const getLink = (item: ObjectWithId) =>
  `/tickets/${getIdFromGraphQLId(item.id)}`

const { goToItem, goToItemLinkColumn, loadMore, resort, storageKeyId } =
  useListTable(props, emit, getLink)

const { config } = storeToRefs(useApplicationStore())

const { bulkEditActive, checkedTicketIds } = useTicketBulkEdit()
</script>

<template>
  <div v-if="loading && !loadingNewPage">
    <slot name="loading">
      <CommonTableSkeleton
        data-test-id="table-skeleton"
        :rows="skeletonLoadingCount"
      />
    </slot>
  </div>

  <template v-else-if="!loading && !items.length">
    <slot name="empty-list" />
  </template>

  <div v-else-if="items.length">
    <CommonAdvancedTable
      v-model:checked-item-ids="checkedTicketIds"
      :has-checkbox-column="bulkEditActive"
      :caption="caption"
      :object="EnumObjectManagerObjects.Ticket"
      :headers="headers"
      :order-by="orderBy"
      :order-direction="orderDirection"
      :group-by="groupBy"
      :reached-scroll-top="reachedScrollTop"
      :scroll-container="scrollContainer"
      :attributes="[
        {
          name: 'priorityIcon',
          label: __('Priority Icon'),
          headerPreferences: {
            noResize: true,
            hideLabel: true,
            displayWidth: 25,
            noSorting: true,
          },
          columnPreferences: {},
          dataType: 'icon',
        },
        {
          name: 'stateIcon',
          label: __('State Icon'),
          headerPreferences: {
            noResize: true,
            hideLabel: true,
            displayWidth: 30,
            noSorting: true,
          },
          columnPreferences: {},
          dataType: 'icon',
        },
      ]"
      :attribute-extensions="{
        title: {
          columnPreferences: {
            link: goToItemLinkColumn,
          },
        },
        number: {
          label: config.ticket_hook,
          columnPreferences: {
            link: goToItemLinkColumn,
          },
        },
      }"
      :items="items"
      :total-items="totalCount"
      :storage-key-id="storageKeyId"
      :max-items="maxItems"
      :is-sorting="resorting"
      @load-more="loadMore"
      @click-row="goToItem"
      @sort="resort"
    >
      <template #column-cell-priorityIcon="{ item, isRowSelected }">
        <CommonTicketPriorityIndicatorIcon
          :ui-color="(item as TicketByList).priority?.uiColor"
          with-text-color
          class="shrink-0 outline-offset-0! group-hover:text-black group-hover:dark:text-white"
          :class="{
            'ltr:text-black rtl:text-black dark:text-white': isRowSelected,
          }"
        />
      </template>
      <template #column-cell-customer_id="{ item, isRowSelected, attribute }">
        <UserPopoverWithTrigger :user="(item as TicketByList).customer" no-link>
          <CommonLabel
            class="block! shrink-0 truncate outline-offset-0! group-hover:text-black! group-hover:dark:text-white!"
            :class="{
              'text-black! dark:text-white!': isRowSelected,
            }"
          >
            <ObjectAttributeContent
              mode="table"
              :attribute="attribute as unknown as ObjectAttribute"
              :object="item"
            />
          </CommonLabel>
        </UserPopoverWithTrigger>
      </template>
      <template #column-cell-stateIcon="{ item, isRowSelected }">
        <CommonTicketStateIndicatorIcon
          class="shrink-0 outline-offset-0! group-hover:text-black group-hover:dark:text-white"
          :class="{
            'text-black! dark:text-white!': isRowSelected,
          }"
          :color-code="(item as TicketByList).stateColorCode"
          :label="(item as TicketByList).state.name"
          :aria-labelledby="(item as TicketByList).id"
          icon-size="tiny"
        />
      </template>
    </CommonAdvancedTable>
  </div>
</template>
