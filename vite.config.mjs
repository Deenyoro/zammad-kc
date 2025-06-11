// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { createRequire } from 'module'
import { readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { homedir } from 'os'

import tailwindcss from '@tailwindcss/vite'
import VuePlugin from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

import svgIconsPlugin from './app/frontend/build/iconsPlugin.mjs'
import ManualChunksPlugin from './app/frontend/build/manualChunks.mjs'
import tsconfig from './tsconfig.base.json' with { type: 'json' }

const dir = dirname(fileURLToPath(import.meta.url))

const SSL_PATH = resolve(homedir(), '.local/state/localhost.rb')

const isEnvBooleanSet = (value) => ['true', '1'].includes(value)

export default defineConfig(({ mode, command }) => {
  const isTesting = ['test', 'cypress'].includes(mode)
  const isBuild = command === 'build'

  const require = createRequire(import.meta.url)

  const plugins = [
    tailwindcss(),
    VuePlugin({
      template: {
        compilerOptions: {
          nodeTransforms:
            isTesting || isEnvBooleanSet(process.env.VITE_TEST_MODE)
              ? []
              : [require('./app/frontend/build/transforms/transformTestId.js')],
        },
      },
    }),
    svgIconsPlugin(),
  ]

  if (!isTesting || isBuild) {
    // Ruby plugin is not needed inside of the vitest context and has some side effects.
    const { default: RubyPlugin } = require('vite-plugin-ruby')
    plugins.push(RubyPlugin())

    plugins.push(
      ...VitePWA({
        disable: isTesting || isEnvBooleanSet(process.env.VITE_TEST_MODE),
        // should be generated on ruby side
        manifest: false,
        registerType: 'prompt',
        srcDir: 'apps/mobile/sw',
        filename: 'sw.ts',
        includeManifestIcons: false,
        injectRegister: null,
        strategies: 'injectManifest',
      }),
    )
    plugins.push(ManualChunksPlugin())
  }

  let https = false

  // vite-ruby controlls this variable, it's either "true" or "false"
  if (isEnvBooleanSet(process.env.VITE_RUBY_HTTPS)) {
    const SSL_CERT = readFileSync(resolve(SSL_PATH, 'localhost.crt'))
    const SSL_KEY = readFileSync(resolve(SSL_PATH, 'localhost.key'))

    https = {
      cert: SSL_CERT,
      key: SSL_KEY,
    }
  }

  let publicDir

  if (!isBuild) {
    publicDir = resolve(dir, 'public')
  }

  return {
    publicDir,
    esbuild: {
      target: isTesting ? 'esnext' : tsconfig.compilerOptions.target,
      // TODO: Remove the following line once the related upstream TailwindCSS issue has been addressed,
      //   since it can mask potential syntax errors.
      //   https://github.com/tailwindlabs/tailwindcss/issues/16582
      logOverride: { 'css-syntax-error': 'silent' },
    },
    build: {
      chunkSizeWarningLimit: 1000, // :TODO - please drop this once working on improving chunks to be smaller then the defaul <500kb
    },
    resolve: {
      preserveSymlinks: isEnvBooleanSet(process.env.PRESERVE_SYMLINKS),
      alias: {
        '^vue-easy-lightbox$':
          'vue-easy-lightbox/dist/external-css/vue-easy-lightbox.esm.min.js',
      },
    },
    server: {
      https,
      watch: {
        ignored: isTesting
          ? []
          : [
              '**/*.spec.*',
              '**/__tests__/**/*',
              (path) =>
                !path.includes('app/frontend') ||
                path.includes('frontend/tests'),
            ],
      },
    },
    define: {
      VITE_TEST_MODE:
        isEnvBooleanSet(process.env.VITEST) ||
        isEnvBooleanSet(process.env.VITE_TEST_MODE),
    },
    test: {
      globals: true,
      // narrowing down test folder speeds up fast-glob in Vitest
      dir: 'app/frontend',
      setupFiles: ['app/frontend/tests/vitest.setup.ts'],
      environment: 'jsdom',
      clearMocks: true,
      css: false,
      testTimeout: isEnvBooleanSet(process.env.CI) ? 30_000 : 5_000,
      unstubGlobals: true,
      onConsoleLog(log) {
        if (
          log.includes('Not implemented: navigation') ||
          log.includes('<Suspense> is an experimental feature')
        )
          return false
      },
    },
    plugins,
  }
})
