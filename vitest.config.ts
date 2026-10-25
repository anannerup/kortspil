import { fileURLToPath } from "node:url"
import { defineConfig } from "vitest/config"

// Frontend unit tests: pure modules only (no DOM). Kept apart from
// vite.config.ts so the Ruby plugin stays out of the test run.
export default defineConfig({
  resolve: { alias: { "~": fileURLToPath(new URL("./app/frontend", import.meta.url)) } },
  test: { include: ["app/frontend/**/*.test.ts"] },
})
