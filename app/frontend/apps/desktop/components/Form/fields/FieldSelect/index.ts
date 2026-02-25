// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import createInput from '#shared/form/core/createInput.ts'
import addLink from '#shared/form/features/addLink.ts'
import addMissingEntityObjectOption from '#shared/form/features/addMissingEntityObjectOption.ts'
import formUpdaterTrigger from '#shared/form/features/formUpdaterTrigger.ts'
import removeValuesForNonExistingOptions from '#shared/form/features/removeValuesForNonExistingOrDisabledOptions.ts'

import FieldSelectInput from './FieldSelectInput.vue'

const fieldDefinition = createInput(
  FieldSelectInput,
  [
    'alternativeBackground',
    'clearable',
    'historicalOptions',
    'multiple',
    'noFiltering',
    'noOptionsLabelTranslation',
    'options',
    'rejectNonExistentValues',
    'sorting',
    'noAutoPreselect',
    'belongsToObjectField',
  ],
  {
    features: [
      addLink,
      formUpdaterTrigger(),
      addMissingEntityObjectOption,
      removeValuesForNonExistingOptions,
    ],
  },
)

export default {
  fieldType: 'select',
  definition: fieldDefinition,
}
