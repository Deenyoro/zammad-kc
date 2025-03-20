<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonPopover from '#shared/components/CommonPopover/CommonPopover.vue'
import type { Props as CommonPopoverProps } from '#shared/components/CommonPopover/CommonPopover.vue'
import { usePopover } from '#shared/components/CommonPopover/usePopover.ts'

import CommonPopoverMenu from '#desktop/components/CommonPopoverMenu/CommonPopoverMenu.vue'

import CommonButton from '../CommonButton/CommonButton.vue'

import type { Props as CommonButtonProps } from '../CommonButton/CommonButton.vue'
import type { Props as CommonPopoverMenuProps } from '../CommonPopoverMenu/CommonPopoverMenu.vue'

export interface Props
  extends CommonButtonProps,
    Pick<CommonPopoverProps, 'hideArrow' | 'orientation' | 'placement'>,
    Pick<CommonPopoverMenuProps, 'items'> {
  addonDisabled?: boolean
  addonLabel?: string
}

const props = withDefaults(defineProps<Props>(), {
  orientation: 'top',
  placement: 'arrowEnd',
})

defineOptions({
  inheritAttrs: false,
})

const separatorClass = computed(() => {
  switch (props.variant) {
    case 'primary':
      return 'border-white'
    case 'tertiary':
      return 'border-gray-300 dark:border-neutral-400'
    case 'submit':
      return 'border-black'
    case 'danger':
      return 'border-red-500'
    case 'remove':
      return 'border-white'
    case 'subtle':
      return 'border-black dark:border-white'
    case 'neutral':
      return 'border-gray-100 dark:border-neutral-400'
    case 'none':
      return 'border-neutral-100 dark:border-gray-900'
    case 'secondary':
    default:
      return 'border-blue-800'
  }
})

const addonPaddingClasses = computed(() => {
  switch (props.size) {
    case 'large':
      return ['px-2!', 'py-3']
    case 'medium':
      return ['px-1.5!', 'py-2.5']
    case 'small':
    default:
      return ['px-1!', 'py-2']
  }
})

const addonIconSize = computed(() => {
  switch (props.size) {
    case 'large':
      return 'small'
    case 'medium':
      return 'tiny'
    case 'small':
    default:
      return 'xs'
  }
})

const { popover, popoverTarget, toggle } = usePopover()
</script>

<template>
  <div class="inline-flex" :class="{ 'w-full': block }">
    <CommonButton
      v-bind="{ ...props, ...$attrs }"
      class="rounded-e-none border-e-[0.5px] hover:z-10 focus-visible:z-10"
      :class="{
        grow: block,
        [separatorClass]: !addonDisabled,
      }"
      :block="false"
    >
      <slot />
    </CommonButton>
    <CommonButton
      ref="popoverTarget"
      v-bind="props"
      class="rounded-s-none border-s-[0.5px]"
      :class="[
        addonPaddingClasses,
        {
          [separatorClass]: !addonDisabled,
        },
      ]"
      :disabled="addonDisabled"
      :block="false"
      type="button"
      :aria-label="$t(addonLabel || __('Context menu'))"
      @click="toggle(true)"
    >
      <CommonIcon
        class="pointer-events-none block shrink-0"
        decorative
        :size="addonIconSize"
        name="chevron-up"
      />
    </CommonButton>
  </div>
  <CommonPopover
    ref="popover"
    :owner="popoverTarget"
    :orientation="orientation"
    :placement="placement"
    :hide-arrow="hideArrow"
  >
    <slot name="popover-content">
      <CommonPopoverMenu :popover="popover" :items="items" />
    </slot>
  </CommonPopover>
</template>
