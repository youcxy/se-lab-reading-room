<script setup>
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import http from '../api'
import { refreshUser, state } from '../store'

const reservations = ref([])
const bills = ref([])
const loading = ref(false)

const statusText = {
  RESERVED: '已预约',
  IN_USE: '使用中',
  TEMP_LEAVE: '暂离中',
  CHECKED_OUT: '已签退',
  EXPIRED: '超时释放',
  CANCELED: '已取消'
}

const statusType = {
  RESERVED: 'warning',
  IN_USE: 'success',
  TEMP_LEAVE: 'info',
  CHECKED_OUT: '',
  EXPIRED: 'danger',
  CANCELED: 'info'
}

const kindText = { USAGE: '按分钟计费', OVERTIME: '超时违约金', DAY_CARD: '包天卡' }

async function load() {
  loading.value = true
  try {
    const [res, billList] = await Promise.all([
      http.get('/reservations', { params: { userId: state.user.id } }),
      http.get('/bills', { params: { userId: state.user.id } })
    ])
    reservations.value = res
    bills.value = billList
    await refreshUser()
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <el-card>
      <template #header>
        <div class="head">
          <span>我的信用与余额</span>
          <el-button size="small" @click="load">刷新</el-button>
        </div>
      </template>
      <el-row :gutter="12">
        <el-col :span="6"><el-statistic title="信用分" :value="state.user.credit" /></el-col>
        <el-col :span="6"><el-statistic title="余额（元）" :value="Number(state.user.balance)" :precision="2" /></el-col>
        <el-col :span="6">
          <el-statistic title="月卡到期" :value="state.user.monthlyExpireDate || '无'" />
        </el-col>
        <el-col :span="6">
          <el-statistic title="包天卡日期" :value="state.user.dayPassDate || '无'" />
        </el-col>
      </el-row>
      <el-alert
        v-if="state.user.credit < 60"
        type="error"
        :closable="false"
        title="信用分低于 60，不能预约座位。违约金与信用扣减只能由系统规则产生，店长与管理员都不能直接改。"
        style="margin-top: 12px"
      />
    </el-card>

    <el-card style="margin-top: 12px">
      <template #header>我的预约与使用记录</template>
      <el-table :data="reservations" size="small" empty-text="还没有预约记录">
        <el-table-column prop="seatCode" label="座位" width="90" />
        <el-table-column label="状态" width="110">
          <template #default="{ row }">
            <el-tag :type="statusType[row.status]" size="small">{{ statusText[row.status] || row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="unitPrice" label="单价（元/小时）" width="140" />
        <el-table-column prop="createdAt" label="预约时间" width="180" />
        <el-table-column prop="expireAt" label="签到截止" width="180" />
        <el-table-column prop="checkinAt" label="签到时间" width="180" />
        <el-table-column prop="checkoutAt" label="签退时间" width="180" />
        <el-table-column label="时长（分钟）" min-width="110">
          <template #default="{ row }">{{ row.minutes || '—' }}</template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-card style="margin-top: 12px">
      <template #header>我的费用明细（每一笔都可以与单价×分钟÷60 对上）</template>
      <el-table :data="bills" size="small" empty-text="还没有账单">
        <el-table-column prop="orderNo" label="订单号" width="170" />
        <el-table-column label="类型" width="130">
          <template #default="{ row }">{{ kindText[row.kind] || row.kind }}</template>
        </el-table-column>
        <el-table-column prop="minutes" label="分钟" width="80" />
        <el-table-column prop="unitPrice" label="单价" width="90" />
        <el-table-column prop="amount" label="金额（元）" width="110" />
        <el-table-column prop="cardType" label="卡券" width="100" />
        <el-table-column label="金额来源" width="150">
          <template #default="{ row }">
            <el-tag :type="row.source === 'CLOUD' ? 'success' : 'info'" size="small">
              {{ row.source === 'CLOUD' ? '华为云函数计算' : '本地兜底' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="createdAt" label="时间" min-width="180" />
      </el-table>
    </el-card>
  </div>
</template>

<style scoped>
.head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
