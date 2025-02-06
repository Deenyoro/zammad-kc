<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<!-- eslint-disable zammad/zammad-detect-translatable-string -->

<script setup lang="ts">
import { getNode, type FormKitNode } from '@formkit/core'
import VueDatePicker, { type DatePickerInstance } from '@vuepic/vue-datepicker'
import { isValid, format, parse } from 'date-fns'
import { isEqual } from 'lodash-es'
import { storeToRefs } from 'pinia'
import { computed, nextTick, ref, toRef, watch } from 'vue'
import { IMask, useIMask } from 'vue-imask'

import useValue from '#shared/components/Form/composables/useValue.ts'
import type { DateTimeContext } from '#shared/components/Form/fields/FieldDate/types.ts'
import { useDateTime } from '#shared/components/Form/fields/FieldDate/useDateTime.ts'
import dateRange from '#shared/form/validation/rules/date-range.ts'
import { EnumTextDirection } from '#shared/graphql/types.ts'
import { i18n } from '#shared/i18n.ts'
import testFlags from '#shared/utils/testFlags.ts'

import { useThemeStore } from '#desktop/stores/theme.ts'

import '@vuepic/vue-datepicker/dist/main.css'

interface Props {
  context: DateTimeContext
}

const props = defineProps<Props>()

const contextReactive = toRef(props, 'context')

const { localValue } = useValue(contextReactive)

const {
  ariaLabels,
  displayFormat,
  is24,
  localeStore,
  minDate,
  position,
  timePicker,
  valueFormat,
} = useDateTime(contextReactive)

const config = computed(() => ({
  keepActionRow: true,
  arrowLeft:
    localeStore.localeData?.dir === EnumTextDirection.Rtl
      ? 'calc(100% - 17px)'
      : '17px',
}))

const actionRow = computed(() => ({
  showSelect: false,
  showCancel: false,
  // Do not show 'Today' for range selection, because it will close the picker
  //   even if only one date was selected.
  showNow: !props.context.range,
  showPreview: false,
}))

const inputIcon = computed(() => {
  if (contextReactive.value.range) return 'calendar-range'
  if (timePicker.value) return 'calendar-date-time'
  return 'calendar-event'
})

const picker = ref<DatePickerInstance>()

const { isDarkMode } = storeToRefs(useThemeStore())

const localeFormat = computed(() => {
  if (timePicker.value) return i18n.getDateTimeFormat()
  return i18n.getDateFormat()
})

// Date/time placeholders used in the locale format:
// - 'dd' - 2-digit day
// - 'd' - day
// - 'mm' - 2-digit month
// - 'm' - month
// - 'yyyy' - year
// - 'yy' - last 2 digits of year
// - 'SS' - 2-digit second
// - 'MM' - 2-digit minute
// - 'HH' - 2-digit hour (24h)
// - 'l' - hour (12h)
// - 'P' - Meridian indicator ('am' or 'pm')
const inputFormat = computed(() =>
  localeFormat.value
    .replace(/MM/, '2DigitMinute') // 'MM' is used for both minute and month
    .replace(/mm/, 'MM')
    .replace(/m/, 'M')
    .replace(/SS/, 'ss')
    .replace(/2DigitMinute/, 'mm')
    .replace(/l/, 'hh')
    .replace(/P/, 'aaa'),
)

const maskOptions = computed(() => ({
  mask: contextReactive.value.range
    ? `${localeFormat.value} - ${localeFormat.value}`
    : localeFormat.value,
  blocks: {
    d: {
      mask: IMask.MaskedRange,
      from: 1,
      to: 31,
      placeholderChar: 'D',
    },
    dd: {
      mask: IMask.MaskedRange,
      from: 1,
      to: 31,
      placeholderChar: 'D',
    },
    m: {
      mask: IMask.MaskedRange,
      from: 1,
      to: 12,
      placeholderChar: 'M',
    },
    mm: {
      mask: IMask.MaskedRange,
      from: 1,
      to: 12,
      placeholderChar: 'M',
    },
    yyyy: {
      mask: IMask.MaskedRange,
      from: 1900,
      to: 2100,
      placeholderChar: 'Y',
    },
    yy: {
      mask: IMask.MaskedRange,
      from: 0,
      to: 99,
      placeholderChar: 'Y',
    },
    ss: {
      mask: IMask.MaskedRange,
      from: 0,
      to: 59,
      placeholderChar: 's',
    },
    MM: {
      mask: IMask.MaskedRange,
      from: 0,
      to: 59,
      placeholderChar: 'm',
    },
    HH: {
      mask: IMask.MaskedRange,
      from: 0,
      to: 23,
      placeholderChar: 'h',
    },
    l: {
      mask: IMask.MaskedRange,
      from: 1,
      to: 12,
      placeholderChar: 'h',
    },
    P: {
      mask: IMask.MaskedEnum,
      enum: ['am', 'pm'],
      placeholderChar: 'p',
    },
  },
  autofix: true,
  lazy: false,
  overwrite: true,
}))

const { el, masked, unmasked } = useIMask(maskOptions)

const parseValue = (value: string) =>
  parse(value, valueFormat.value, new Date())

const formatValue = (value: Date) => format(value, valueFormat.value)

watch(
  localValue,
  (newValue) => {
    if (!newValue) {
      masked.value = '' // clear input
      return
    }

    if (contextReactive.value.range) {
      const [startValue, endValue] = newValue
      if (!startValue || !endValue) return

      const startDate = parseValue(startValue)
      const endDate = parseValue(endValue)
      if (!isValid(startDate) || !isValid(endDate)) return

      const value = `${format(startDate, inputFormat.value)} - ${format(endDate, inputFormat.value)}`
      if (masked.value === value) return

      masked.value = `${format(startDate, inputFormat.value)} - ${format(endDate, inputFormat.value)}`

      return
    }

    const newDate = parseValue(newValue)
    const maskedDate = parse(masked.value, inputFormat.value, new Date())

    if (
      isValid(maskedDate) &&
      maskedDate.toISOString() === newDate.toISOString()
    )
      return

    masked.value = format(newDate, inputFormat.value)
  },
  {
    immediate: true,
  },
)

const dateRangeValidation = (value: (string | undefined)[]) => {
  if (value.includes(undefined)) return false
  if (dateRange.rule({ value } as FormKitNode<string[]>)) return true

  const node = getNode(contextReactive.value.id)
  if (!node) return

  // Manually set validation error message.
  node.setErrors(i18n.t(dateRange.localeMessage()))

  return false
}

watch(masked, (newValue) => {
  // empty input
  if (localValue.value && (!newValue || !unmasked.value)) {
    localValue.value = null
    return
  }

  if (contextReactive.value.range) {
    const newValues = newValue.split(' - ').map((value) => {
      const date = parse(value, inputFormat.value, new Date())
      if (!isValid(date)) return
      return formatValue(date)
    })

    if (!dateRangeValidation(newValues) || isEqual(localValue.value, newValues))
      return

    localValue.value = newValues

    return
  }

  const newDate = parse(newValue, inputFormat.value, new Date())

  if (
    !isValid(newDate) ||
    (isValid(newDate) && localValue.value === formatValue(newDate))
  )
    return

  localValue.value = formatValue(newDate)
})

const open = () => {
  nextTick(() => {
    testFlags.set('field-date-time.opened')
  })
}

const closed = () => {
  nextTick(() => {
    testFlags.set('field-date-time.closed')
  })

  if (!localValue.value && masked.value) {
    masked.value = '' // clear input
    return
  }

  if (contextReactive.value.range) {
    const maskedValues = masked.value.split(' - ').map((value: string) => {
      const date = parse(value, inputFormat.value, new Date())
      if (!isValid(date)) return
      return formatValue(date)
    })

    if (isEqual(localValue.value, maskedValues)) return

    const [startValue, endValue] = localValue.value
    if (!startValue || !endValue) return

    const startDate = parseValue(startValue)
    const endDate = parseValue(endValue)
    if (!isValid(startDate) || !isValid(endDate)) return

    masked.value = `${format(startDate, inputFormat.value)} - ${format(endDate, inputFormat.value)}`

    return
  }

  const maskedDate = parse(masked.value, inputFormat.value, new Date())

  if (isValid(maskedDate) && localValue.value === formatValue(maskedDate))
    return

  const newDate = parseValue(localValue.value)
  masked.value = format(newDate, inputFormat.value)
}
</script>

<template>
  <div class="w-full">
    <!-- eslint-disable vuejs-accessibility/aria-props   -->
    <VueDatePicker
      ref="picker"
      v-model="localValue"
      :uid="context.id"
      :model-type="valueFormat"
      :name="context.node.name"
      :clearable="!!context.clearable"
      :disabled="context.disabled"
      :range="context.range"
      :enable-time-picker="timePicker"
      :format="displayFormat"
      :is-24="is24"
      :dark="isDarkMode"
      :locale="i18n.locale()"
      :max-date="context.maxDate"
      :min-date="minDate"
      :start-date="minDate || context.maxDate"
      :ignore-time-validation="!timePicker"
      :prevent-min-max-navigation="
        Boolean(minDate || context.maxDate || context.futureOnly)
      "
      :now-button-label="$t('Today')"
      :position="position"
      :action-row="actionRow"
      :config="config"
      :aria-labels="ariaLabels"
      :text-input="{ openMenu: 'open' }"
      auto-apply
      offset="12"
      @open="open"
      @closed="closed"
      @blur="context.handlers.blur"
    >
      <template #dp-input>
        <input
          :id="context.id"
          ref="el"
          :name="context.node.name"
          :class="context.classes.input"
          :disabled="context.disabled"
          :aria-describedby="context.describedBy"
          v-bind="context.attrs"
          type="text"
        />
      </template>
      <template #input-icon>
        <CommonIcon
          :name="inputIcon"
          size="tiny"
          decorative
          @click.stop="picker?.toggleMenu()"
        />
      </template>
      <template #clear-icon>
        <CommonIcon
          class="me-3"
          name="x-lg"
          size="xs"
          tabindex="0"
          role="button"
          :aria-label="$t('Clear Selection')"
          @click.stop="picker?.clearValue()"
        />
      </template>
      <template #clock-icon>
        <CommonIcon name="clock" size="tiny" decorative />
      </template>
      <template #calendar-icon>
        <CommonIcon name="calendar" size="tiny" decorative />
      </template>
      <template #arrow-left>
        <CommonIcon name="chevron-left" size="xs" decorative />
      </template>
      <template #arrow-right>
        <CommonIcon name="chevron-right" size="xs" decorative />
      </template>
      <template #arrow-up>
        <CommonIcon name="chevron-up" size="xs" decorative />
      </template>
      <template #arrow-down>
        <CommonIcon name="chevron-down" size="xs" decorative />
      </template>
    </VueDatePicker>
  </div>
</template>

<style scoped>
:deep(.dp__theme_light) {
  --dp-background-color: theme(colors.white);
  --dp-text-color: theme(colors.black);
  --dp-hover-color: theme(colors.blue.600);
  --dp-hover-text-color: theme(colors.black);
  --dp-hover-icon-color: theme(colors.blue.800);
  --dp-primary-color: theme(colors.blue.800);
  --dp-primary-disabled-color: theme(colors.blue.500);
  --dp-primary-text-color: theme(colors.white);
  --dp-secondary-color: theme(colors.stone.200);
  --dp-border-color: theme(colors.transparent);
  --dp-menu-border-color: theme(colors.neutral.100);
  --dp-border-color-hover: theme(colors.transparent);
  --dp-disabled-color: theme(colors.transparent);
  --dp-disabled-color-text: theme(colors.stone.200);
  --dp-scroll-bar-background: theme(colors.blue.200);
  --dp-scroll-bar-color: theme(colors.stone.200);
  --dp-success-color: theme(colors.green.500);
  --dp-success-color-disabled: theme(colors.green.300);
  --dp-icon-color: theme(colors.stone.200);
  --dp-danger-color: theme(colors.red.500);
  --dp-marker-color: theme(colors.blue.600);
  --dp-tooltip-color: theme(colors.blue.200);
  --dp-highlight-color: theme(colors.blue.800);
  --dp-range-between-dates-background-color: theme(colors.blue.500);
  --dp-range-between-dates-text-color: theme(colors.blue.800);
  --dp-range-between-border-color: theme(colors.neutral.100);
  --dp-input-background-color: theme(colors.blue.200);

  .dp {
    &--clear-btn:hover {
      color: theme(colors.black);
    }

    &__btn,
    &__calendar_item,
    &__action_button {
      &:hover {
        outline-color: theme(colors.blue.600);
      }

      &:focus {
        outline-color: theme(colors.blue.800);
      }
    }

    &__button,
    &__action_button {
      color: theme(colors.gray.300);
      background: theme(colors.green.200);
    }
  }
}

:deep(.dp__theme_dark) {
  --dp-background-color: theme(colors.gray.500);
  --dp-text-color: theme(colors.white);
  --dp-hover-color: theme(colors.blue.900);
  --dp-hover-text-color: theme(colors.white);
  --dp-hover-icon-color: theme(colors.blue.800);
  --dp-primary-color: theme(colors.blue.800);
  --dp-primary-disabled-color: theme(colors.blue.950);
  --dp-primary-text-color: theme(colors.white);
  --dp-secondary-color: theme(colors.neutral.500);
  --dp-border-color: theme(colors.transparent);
  --dp-menu-border-color: theme(colors.gray.900);
  --dp-border-color-hover: theme(colors.transparent);
  --dp-disabled-color: theme(colors.transparent);
  --dp-disabled-color-text: theme(colors.neutral.500);
  --dp-scroll-bar-background: theme(colors.gray.700);
  --dp-scroll-bar-color: theme(colors.gray.400);
  --dp-success-color: theme(colors.green.500);
  --dp-success-color-disabled: theme(colors.green.900);
  --dp-icon-color: theme(colors.neutral.500);
  --dp-danger-color: theme(colors.red.500);
  --dp-marker-color: theme(colors.blue.700);
  --dp-tooltip-color: theme(colors.gray.700);
  --dp-highlight-color: theme(colors.blue.800);
  --dp-range-between-dates-background-color: theme(colors.blue.950);
  --dp-range-between-dates-text-color: theme(colors.blue.800);
  --dp-range-between-border-color: theme(colors.gray.900);
  --dp-input-background-color: theme(colors.gray.700);

  .dp {
    &--clear-btn:hover {
      color: theme(colors.white);
    }

    &__btn,
    &__calendar_item,
    &__action_button {
      &:hover {
        outline-color: theme(colors.blue.900);
      }

      &:focus {
        outline-color: theme(colors.blue.800);
      }
    }

    &__button,
    &__action_button {
      color: theme(colors.neutral.400);
      background: theme(colors.gray.600);
    }
  }
}

:deep(.dp__main) {
  /* stylelint-disable value-keyword-case */
  --dp-font-family: theme(fontFamily.sans);
  --dp-border-radius: theme(borderRadius.lg);
  --dp-cell-border-radius: theme(borderRadius.md);
  --dp-button-height: theme(size.6);
  --dp-month-year-row-height: theme(size.7);
  --dp-month-year-row-button-size: theme(size.7);
  --dp-button-icon-height: theme(height.4);
  --dp-cell-size: theme(size.6);
  --dp-cell-padding: theme(padding.2);
  --dp-common-padding: theme(padding.2);
  --dp-input-icon-padding: theme(padding.2);
  --dp-input-padding: var(--dp-common-padding);
  --dp-menu-min-width: 210px;
  --dp-action-buttons-padding: theme(padding.3);
  --dp-row-margin: theme(margin.2) theme(margin.0);
  --dp-calendar-header-cell-padding: theme(padding.2);
  --dp-two-calendars-spacing: theme(spacing[2.5]);
  --dp-overlay-col-padding: theme(padding.2);
  --dp-time-inc-dec-button-size: theme(size.7);
  --dp-menu-padding: theme(padding.2);
  --dp-font-size: theme(fontSize.sm);
  --dp-preview-font-size: theme(fontSize.xs);
  --dp-time-font-size: theme(fontSize.base);

  .dp {
    &__input_wrap {
      display: flex;
    }

    &__input_icon {
      left: unset;
      right: theme(space[2.5]);

      &:where([dir='rtl'], [dir='rtl'] *) {
        left: theme(space[2.5]);
        right: unset;
      }

      &_pad {
        padding-inline-start: var(--dp-common-padding);
        padding-inline-end: var(--dp-input-icon-padding);
      }
    }

    &--clear-btn {
      right: theme(space.6);

      &:where([dir='rtl'], [dir='rtl'] *) {
        left: theme(space.6);
        right: unset;
      }
    }

    &--tp-wrap {
      padding: var(--dp-common-padding);
      max-width: none;
    }

    &__inner_nav:hover,
    &__month_year_select:hover,
    &__year_select:hover,
    &__date_hover:hover,
    &__inc_dec_button {
      background: theme(colors.transparent);
      transition: none;
    }

    &__date_hover.dp__cell_offset:hover {
      color: var(--dp-secondary-color);
    }

    &__menu_inner {
      padding-bottom: 0;
    }

    &__action_row {
      padding-top: 0;
      margin-top: theme(space[0.5]);
    }

    &__btn,
    &__button,
    &__calendar_item,
    &__action_button {
      transition: none;
      border-radius: theme(borderRadius.md);
      outline-color: theme(colors.transparent);

      &:hover {
        outline-width: 1px;
        outline-style: solid;
        outline-offset: 1px;
      }

      &:focus {
        outline-width: 1px;
        outline-style: solid;
        outline-offset: 1px;
      }
    }

    &__calendar_row {
      gap: theme(gap[1.5]);
    }

    &__month_year_wrap {
      gap: theme(gap.2);
    }

    &__time_col {
      gap: theme(gap.3);
    }

    &__today {
      border: none;
      color: theme(colors.blue.800);

      &.dp__range_start,
      &.dp__range_end,
      &.dp__active_date {
        color: theme(colors.white);
      }
    }

    &__action_buttons {
      margin-inline-start: 0;
      flex-grow: 1;
    }

    &__action_button {
      margin-inline-start: 0;
      transition: none;
      flex-grow: 1;
      display: inline-flex;
      justify-content: center;
      border-radius: theme(borderRadius.md);
    }

    &__action_cancel {
      border: 0;
    }

    &--arrow-btn-nav .dp__inner_nav {
      color: theme(colors.blue.800);
    }

    /* NB: Fix orientation of the popover arrow in RTL locales. */
    &__arrow {
      &_top:where([dir='rtl'], [dir='rtl'] *) {
        transform: translate(-50%, -50%) rotate(-45deg);
      }

      &_bottom:where([dir='rtl'], [dir='rtl'] *) {
        transform: translate(-50%, 50%) rotate(45deg);
      }
    }

    &__overlay_container {
      padding-bottom: theme(padding.2);
    }

    &__overlay_container + .dp__button,
    &__overlay_row + .dp__button {
      width: auto;
      margin: theme(margin.2);
    }

    &__overlay_container + .dp__button {
      width: calc(var(--dp-menu-min-width));
    }

    &__time_display {
      transition: none;
      padding: theme(padding.2);
    }

    &__range_start,
    &__range_end,
    &__range_between {
      transition: none;
      border: none;
      border-radius: theme(borderRadius.md);
    }

    &__range_between:hover {
      background: var(--dp-range-between-dates-background-color);
      color: var(--dp-range-between-dates-text-color);
    }

    &__range_end,
    &__range_start,
    &__active_date {
      &.dp__cell_offset {
        color: var(--dp-primary-text-color);
      }
    }

    &__calendar_header {
      font-weight: 400;
      text-transform: uppercase;
    }
  }
}
</style>
