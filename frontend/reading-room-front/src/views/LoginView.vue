<script setup>
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import http from '../api'
import { setUser } from '../store'

const router = useRouter()
const form = reactive({ login: 's001', password: '123456' })
const loading = ref(false)

const demoAccounts = [
  { login: 's001', label: '张三（普通自习人员，余额 200）' },
  { login: 's002', label: '李四（普通自习人员）' },
  { login: 's003', label: '王五（月卡有效期内）' },
  { login: 's004', label: '赵六（今天有包天卡）' },
  { login: 's005', label: '钱七（信用 55，不能预约）' },
  { login: 'm001', label: '店长（单价、投诉、看板）' },
  { login: 'a001', label: '管理员（维护座位）' }
]

async function submit() {
  loading.value = true
  try {
    const user = await http.post('/auth/login', { login: form.login, password: form.password })
    setUser(user)
    ElMessage.success(`欢迎，${user.displayName}`)
    router.push('/seats')
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}

function quick(login) {
  form.login = login
  form.password = '123456'
  submit()
}

onMounted(() => {
  form.login = 's001'
})
</script>

<template>
  <div class="login-wrap">
    <el-card class="login-card">
      <h2>智能共享自习室管理系统</h2>
      <p class="sub">项目编号 26 · 软件工程实验 · 课程原型</p>

      <el-form :model="form" label-width="72px" @submit.prevent="submit">
        <el-form-item label="账号">
          <el-input v-model="form.login" placeholder="例如 s001" />
        </el-form-item>
        <el-form-item label="密码">
          <el-input v-model="form.password" type="password" show-password placeholder="123456" />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :loading="loading" style="width: 100%" @click="submit">登录</el-button>
        </el-form-item>
      </el-form>

      <el-divider>一键用演示账号登录</el-divider>
      <div class="quick">
        <el-button v-for="acc in demoAccounts" :key="acc.login" size="small" @click="quick(acc.login)">
          {{ acc.label }}
        </el-button>
      </div>
    </el-card>
  </div>
</template>

<style scoped>
.login-wrap {
  display: flex;
  justify-content: center;
  padding-top: 48px;
}
.login-card {
  width: 560px;
}
h2 {
  margin: 8px 0 4px;
  text-align: center;
  color: #303133;
}
.sub {
  text-align: center;
  color: #909399;
  margin-top: 0;
  margin-bottom: 20px;
}
.quick {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.quick .el-button {
  margin-left: 0;
}
</style>
