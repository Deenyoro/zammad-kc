// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import getUuid from '#shared/utils/getUuid.ts'

/* eslint-disable zammad/zammad-detect-translatable-string */

// :TODO - Move and adjust highlight colors, when we work on this story
export const highlightColors = [
  {
    value: { light: '#f7e7b2', dark: 'rgba(247,231,178,0.3)' },
    name: 'Dairy Cream',
    label: 'Yellow',
    id: getUuid(),
  },
  {
    value: {
      light: '#bce7b6',
      dark: 'rgba(188,231,182,0.3)',
    },
    name: 'Celadon',
    label: 'Green',
    id: getUuid(),
  },
  {
    value: {
      light: '#b3ddf9',
      dark: 'rgba(179,221,249,0.3)',
    },
    name: 'Sail',
    label: 'Blue',
    id: getUuid(),
  },
  {
    value: {
      light: '#fea9c5',
      dark: 'rgba(254,169,197,0.3)',
    },
    name: 'Carnation Pink',
    label: 'Pink',
    id: getUuid(),
  },
  {
    value: {
      light: '#eac5ee',
      dark: 'rgba(234,197,238,0.3)',
    },
    name: 'French Lilac',
    label: 'Purple',
    id: getUuid(),
  },
]
