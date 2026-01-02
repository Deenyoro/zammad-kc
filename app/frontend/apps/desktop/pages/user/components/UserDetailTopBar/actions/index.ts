// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import type { UserInfoActionPlugin } from './types.ts'

const pluginModules = import.meta.glob<UserInfoActionPlugin>(
  ['./*.ts', '!./index.ts', '!./types.ts'],
  {
    eager: true,
    import: 'default',
  },
)

const sortedActionPlugins = Object.values(pluginModules).sort((p1, p2) => p1.order - p2.order)

const topLevelActions: UserInfoActionPlugin[] = []

const secondLevelActions: UserInfoActionPlugin[] = []

sortedActionPlugins.forEach((plugin) =>
  plugin.topLevel ? topLevelActions.push(plugin) : secondLevelActions.push(plugin),
)

export const initializeActionPlugins = () => {
  sortedActionPlugins.forEach((plugin) => plugin.initialize?.())

  return { topLevelActions, secondLevelActions }
}
