import { fileURLToPath } from 'node:url'
import { mergeConfig, defineConfig, configDefaults } from 'vitest/config'
import viteConfig from './vite.config'

export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      reporters: ['default', 'junit', "html", "json"],
      outputFile: {
        junit: 'coverages/unit-tests.xml',
      },
      coverage: {
        provider: 'v8',
        reporter: ['text', 'json', 'lcov'],
        reportsDirectory: './coverages/coverage',
      },
      environment: 'jsdom',
      exclude: [...configDefaults.exclude, 'e2e/**'],
      root: fileURLToPath(new URL('./', import.meta.url)),
    },
  }),
)
