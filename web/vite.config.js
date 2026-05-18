import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  base: './',
  build: {
    outDir: '../ui',
    emptyOutDir: true,
    target: 'chrome69',
    cssTarget: 'chrome69',
  },
})
