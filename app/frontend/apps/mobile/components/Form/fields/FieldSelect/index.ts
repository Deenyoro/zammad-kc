// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import createInput from '#shared/form/core/createInput.ts'
import addLink from '#shared/form/features/addLink.ts'
import addMissingInitialOption from '#shared/form/features/addMissingEntityObjectOption.ts'
import formUpdaterTrigger from '#shared/form/features/formUpdaterTrigger.ts'
import removeValuesForNonExistingOptions from '#shared/form/features/removeValuesForNonExistingOrDisabledOptions.ts'

import FieldSelectInput from './FieldSelectInput.vue'

const fieldDefinition = createInput(
  FieldSelectInput,
  [
    'clearable',
    'historicalOptions',
    'multiple',
    'noOptionsLabelTranslation',
    'options',
    'rejectNonExistentValues',
    'sorting',
    'noAutoPreselect',
  ],
  {
    features: [
      addLink,
      formUpdaterTrigger(),
      addMissingInitialOption,
      removeValuesForNonExistingOptions,
    ],
  },
  {
    addArrow: true,
  },
)

export default {
  fieldType: 'select',
  definition: fieldDefinition,
}
