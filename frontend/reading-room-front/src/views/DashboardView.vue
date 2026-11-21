<script setup>
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import http from '../api'

const range = ref([])
const summary = ref(null)
const orders = ref([])
const loading = ref(false)

async function load() {
  loading.value = true
  try {
    const params = {}
    if (range.value && range.value.length === 2) {
      params.from = range.value[0]
      params.to = range.value[1]
    }
    const [s, o] = await Promise.all([
      http.get('/dashboard', { params }),
      http.get('/dashboard/orders', { params })
    ])
    summary.value = s
    orders.value = o
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}

const kindText = { USAGE: '按分钟', OVERTIME: '超时违约金', DAY_CARD: '包天卡' }

// 云函数面板：手工触发定时触发器与手工调用计费函数，用于演示“定时与手工结果一致”
const quoteMinutes = ref(30)
const quotePrice = ref(4)
const quote = ref(null)
const timeoutResult = ref(null)
const busyQuote = ref(false)
const busyTimeout = ref(false)

async function runQuote() {
  busyQuote.value = true
  try {
    quote.value = await http.post('/cloud/quote', {
      unitPrice: Number(quotePrice.value),
      minutes: Number(quoteMinutes.value)
    })
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    busyQuote.value = false
  }
}

async function runTimeout() {
  busyTimeout.value = true
  try {
    timeoutResult.value = await http.post('/timeout/run')
    if (timeoutResult.value && timeoutResult.value.handled > 0) {
      ElMessage.success(`已释放 ${timeoutResult.value.handled} 个预约后 15 分钟未签到的座位`)
    } else {
      ElMessage.info('没有需要释放的超时座位（重复触发不会产生第二条记录）')
    }
    await load()
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    busyTimeout.value = false
  }
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <el-card>
      <template #header>
        <div class="head">
          <span>经营看板（订单数、客单价、复购人数与订单明细同源）</span>
          <div class="tools">
            <el-date-picker
              v-model="range"
              type="daterange"
              value-format="YYYY-MM-DD"
              start-placeholder="开始日期"
              end-placeholder="结束日期"
              size="small"
              style="width: 260px"
            />
            <el-button size="small" type="primary" @click="load">查询</el-button>
          </div>
        </div>
      </template>

      <el-row v-if="summary" :gutter="12">
        <el-col :span="6"><el-statistic title="订单数" :value="summary.orders" /></el-col>
        <el-col :span="6">
          <el-statistic title="营收（元）" :value="Number(summary.revenue)" :precision="2" />
        </el-col>
        <el-col :span="6">
          <el-statistic title="客单价（元）" :value="Number(summary.avgTicket)" :precision="2" />
        </el-col>
        <el-col :span="6"><el-statistic title="复购人数" :value="summary.repeatUsers" /></el-col>
      </el-row>

      <el-row v-if="summary" :gutter="12" style="margin-top: 16px">
        <el-col :span="6"><el-statistic title="占用座位" :value="summary.occupied" /></el-col>
        <el-col :span="6"><el-statistic title="座位总数" :value="summary.total" /></el-col>
        <el-col :span="6">
          <el-statistic title="上座率" :value="Number(summary.occupancyRate) * 100" :precision="0" suffix="%" />
        </el-col>
        <el-col :span="6">
          <el-statistic title="当前单价（元/小时）" :value="Number(summary.currentPrice)" :precision="2" />
        </el-col>
      </el-row>

      <el-alert style="margin-top: 12px" type="info" :closable="false"
                title="口径：客单价 = 营收 ÷ 订单数；复购人数 = 所选日期内订单不少于 2 笔的人数；待处理投诉数一并纳入看板。" />

      <p v-if="summary" class="pending">当前待处理投诉：{{ summary.pendingComplaints }} 条</p>
    </el-card>

    <el-card style="margin-top: 12px">
      <template #header>云函数（FunctionGraph）演示</template>
      <el-row :gutter="16">
        <el-col :span="12">
          <p class="label">① 手工调用计费函数（金额 = 单价 × 分钟 ÷ 60）</p>
          <div class="inline">
            <span>单价</span>
            <el-input-number v-model="quotePrice" :min="0" :step="0.4" :precision="2" size="small" controls-position="right" />
            <span>分钟</span>
            <el-input-number v-model="quoteMinutes" :min="1" :step="5" size="small" controls-position="right" />
            <el-button size="small" type="primary" :loading="busyQuote" @click="runQuote">调用云函数</el-button>
          </div>
          <el-alert
            v-if="quote"
            style="margin-top: 8px"
            type="success"
            :closable="false"
            :title="`云端返回 ${quote.amount} 元，来源 ${quote.source}${quote.detail ? '（' + quote.detail + '）' : ''}`"
          />
        </el-col>
        <el-col :span="12">
          <p class="label">② 手工触发“释放超时座位”定时任务（与每日定时触发器同一逻辑）</p>
          <div class="inline">
            <el-button size="small" type="warning" :loading="busyTimeout" @click="runTimeout">手工触发一次</el-button>
            <span v-if="timeoutResult" class="result">
              本次处理 {{ timeoutResult.handled }} 条，信用扣分与违约金已按 15 分钟规则处理
            </span>
          </div>
          <el-alert
            style="margin-top: 8px"
            type="info"
            :closable="false"
            title="同一超时事件重复触发不会新增账单或信用流水（由唯一键保证）"
          />
        </el-col>
      </el-row>
    </el-card>

    <el-card style="margin-top: 12px">
      <template #header>订单明细</template>
      <el-table :data="orders" size="small" empty-text="该日期区间没有订单">
        <el-table-column prop="order_no" label="订单号" width="170" />
        <el-table-column prop="user_name" label="用户" width="110" />
        <el-table-column prop="seat_code" label="座位" width="80" />
        <el-table-column label="类型" width="110">
          <template #default="{ row }">{{ kindText[row.kind] || row.kind }}</template>
        </el-table-column>
        <el-table-column prop="minutes" label="分钟" width="80" />
        <el-table-column prop="unit_price" label="单价" width="90" />
        <el-table-column prop="amount" label="金额" width="100" />
        <el-table-column prop="source" label="来源" width="100" />
        <el-table-column prop="created_at" label="时间" min-width="180" />
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
.tools {
  display: flex;
  gap: 8px;
}
.pending {
  color: #e6a23c;
  margin-bottom: 0;
}
.label {
  margin: 0 0 8px;
  color: #303133;
  font-weight: 600;
}
.inline {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.result {
  color: #606266;
}
</style>
