<script setup>
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import http from './api'
import { isManager, logout, refreshClock, state } from './store'

const router = useRouter()
const advancing = ref(false)

const navs = [
  { path: '/seats', label: '座位与预约' },
  { path: '/me', label: '我的记录' },
  { path: '/complaints', label: '投诉处理' },
  { path: '/dashboard', label: '店长看板' },
  { path: '/pricing', label: '上座率与调价' }
]

async function tick() {
  try {
    await refreshClock()
  } catch (e) {
    /* 登录页没有后端数据也不报错 */
  }
}

async function advance(minutes) {
  advancing.value = true
  try {
    const clock = await http.put('/clock', { advanceMinutes: minutes })
    state.businessTime = clock.businessTime
    ElMessage.success(`模拟时间已推进 ${minutes} 分钟`)
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    advancing.value = false
  }
}

async function resetClock() {
  advancing.value = true
  try {
    const clock = await http.post('/clock/reset', {})
    state.businessTime = clock.businessTime
    ElMessage.success('模拟时间已恢复为服务器时间')
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    advancing.value = false
  }
}

function doLogout() {
  logout()
  router.push('/login')
}

onMounted(tick)
</script>

<template>
  <el-container class="app">
    <el-header class="app-header">
      <div class="brand">
        <span class="logo">26</span>
        <span class="title">智能共享自习室管理系统</span>
      </div>

      <el-menu mode="horizontal" :ellipsis="false" router :default-active="$route.path" class="menu">
        <el-menu-item v-for="nav in navs" :key="nav.path" :index="nav.path">
          {{ nav.label }}
        </el-menu-item>
      </el-menu>

      <div class="right">
        <el-tooltip content="页面上的模拟时间只影响业务时间，不改服务器时间" placement="bottom">
          <el-tag type="info" class="clock">{{ state.businessTime || '业务时间加载中' }}</el-tag>
        </el-tooltip>
        <el-button-group>
          <el-button size="small" :loading="advancing" @click="advance(15)">+15 分钟</el-button>
          <el-button size="small" :loading="advancing" @click="advance(30)">+30 分钟</el-button>
          <el-button size="small" :loading="advancing" @click="resetClock">重置时间</el-button>
        </el-button-group>

        <template v-if="state.user">
          <el-tag :type="isManager ? 'warning' : 'success'">
            {{ state.user.displayName }}（{{ state.user.role === 'MEMBER' ? '自习人员' : state.user.role === 'MANAGER' ? '店长' : '管理员' }}）
          </el-tag>
          <el-button size="small" @click="doLogout">退出</el-button>
        </template>
      </div>
    </el-header>

    <el-main class="app-main">
      <router-view />
    </el-main>

    <el-footer class="app-footer">
      软件工程实验 · 项目编号 26 · 金额由华为云函数工作流计算（本地演示用 mock FunctionGraph）
    </el-footer>
  </el-container>
</template>

<style>
body {
  margin: 0;
  background: #f5f7fa;
  font-family: 'Microsoft YaHei', 'PingFang SC', Arial, sans-serif;
}
.app-header {
  display: flex;
  align-items: center;
  gap: 16px;
  background: #fff;
  border-bottom: 1px solid #e4e7ed;
  height: 60px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 8px;
  white-space: nowrap;
}
.logo {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: #409eff;
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
}
.title {
  font-size: 17px;
  font-weight: 700;
  color: #303133;
}
.menu {
  border-bottom: none;
  flex: 1;
}
.right {
  display: flex;
  align-items: center;
  gap: 8px;
  white-space: nowrap;
}
.clock {
  font-family: Consolas, monospace;
}
.app-main {
  padding: 16px 24px;
}
.app-footer {
  text-align: center;
  color: #909399;
  font-size: 12px;
  line-height: 40px;
  height: 40px;
}
</style>
