import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    host: '127.0.0.1',
    watch: {
      // 编辑器/工具写文件时会留下临时目录，避免 watcher 因 EBUSY 崩溃
      ignored: ['**/*.tmpdir/**', '**/*.tmp', '**/.~*']
    },
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true
      }
    }
  }
})
