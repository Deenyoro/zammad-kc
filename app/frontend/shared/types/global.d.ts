// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

declare type LogLevel = 'trace' | 'debug' | 'info' | 'warn' | 'error' | 'silent'

declare type Maybe<T> = T | null

declare type ID = string

declare global {
  interface Window {
    __(source: string): string
    setLogLevel(level: LogLevel, persistent: boolean): void
    setQueryPollingConfig(
      config?: Partial<QueryPollingConfig>,
    ): QueryPollingConfig
  }
}

declare function __(source: string): string
declare function setLogLevel(level: LogLevel, persistent: boolean): void

declare function setQueryPollingConfig(
  config?: Partial<QueryPollingConfig>,
): QueryPollingConfig

// TODO: Workaround for current problem with formkit version, remove when fixed
declare module '@formkit/themes'
