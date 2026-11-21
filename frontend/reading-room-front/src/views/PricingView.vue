<script setup>
import { computed, onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import http from '../api'
import { isManager, state } from '../store'

const status = ref(null)
const changes = ref([])
const loading = ref(false)
const busy = ref(false)

const ratePercent = computed(() => (status.value ? (Number(status.value.occupancyRate) * 100).toFixed(1) : '0.0'))

async function load() {
  loading.value = true
  try {
    const [s, c] = await Promise.all([http.get('/pricing/status'), http.get('/pricing/changes')])
    status.value = s
    changes.value = c
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}

async function adjust() {
  busy.value = true
  try {
    const change = await http.post('/pricing/adjust', { operatorId: state.user.id })
    if (change) {
      ElMessage.success(`已调整：${change.oldPrice} → ${change.newPrice} 元/小时`)
    } else {
      ElMessage.info('当前不需要调价（未超过 80% 或价格已经是正确值），未产生变价记录')
    }
    await load()
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    busy.value = false
  }
}

function exportCsv() {
  window.open('/api/pricing/changes/export', '_blank')
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <el-card>
      <template #header>
        <div class="head">
          <span>上座率与调价（超过 80% 单价 ×1.2）</span>
          <div>
            <el-button size="small" @click="load">刷新</el-button>
            <el-button size="small" type="primary" :disabled="!isManager" :loading="busy" @click="adjust">
              按当前上座率调价
            </el-button>
            <el-button size="small" @click="exportCsv">导出变价记录 CSV</el-button>
          </div>
        </div>
      </template>

      <el-row v-if="status" :gutter="12">
        <el-col :span="4"><el-statistic title="占用座位" :value="status.occupied" /></el-col>
        <el-col :span="4"><el-statistic title="座位总数" :value="status.total" /></el-col>
        <el-col :span="5"><el-statistic title="上座率" :value="ratePercent" suffix="%" /></el-col>
        <el-col :span="4"><el-statistic title="阈值" :value="Number(status.threshold) * 100" suffix="%" :precision="0" /></el-col>
        <el-col :span="3"><el-statistic title="当前单价" :value="Number(status.currentPrice)" :precision="2" /></el-col>
        <el-col :span="4"><el-statistic title="按上座率应为" :value="Number(status.expectedPrice)" :precision="2" /></el-col>
      </el-row>

      <el-alert
        v-if="status"
        style="margin-top: 12px"
        :type="status.shouldChange ? 'warning' : 'success'"
        :closable="false"
        :title="
          status.shouldChange
            ? `上座率 ${ratePercent}% 已超过 80%，点“按当前上座率调价”会写一条变价记录`
            : '未超过 80% 或价格已是正确值：不会产生变价记录'
        "
      />
    </el-card>

    <el-card style="margin-top: 12px">
      <template #header>变价记录（每次变价一条，可按日导出）</template>
      <el-table :data="changes" size="small" empty-text="还没有变价记录">
        <el-table-column prop="id" label="编号" width="70" />
        <el-table-column prop="occupied" label="占用数" width="90" />
        <el-table-column prop="totalSeats" label="座位总数" width="100" />
        <el-table-column prop="occupancyRate" label="上座率" width="100" />
        <el-table-column prop="oldPrice" label="原价" width="90" />
        <el-table-column prop="newPrice" label="新价" width="90" />
        <el-table-column prop="operator" label="操作人" width="110" />
        <el-table-column prop="createdAt" label="时间" min-width="180" />
      </el-table>
    </el-card>

    <el-card style="margin-top: 12px">
      <template #header>调价规则</template>
      <ul class="rules">
        <li>上座率 = 占用座位数 ÷ 座位总数，超过 80% 时单价 ×1.2（9 / 10 = 90%，4.00 → 4.80）。</li>
        <li>未超过 80% 时不涨价，也不产生变价记录。</li>
        <li>涨价只适用于涨价之后新开始的使用：预约时会把当时单价快照写入预约，中途涨价不影响已开始的计费。</li>
        <li>导出内容包含占用数、座位总数、调整后单价，可交给店长按日核对。</li>
      </ul>
    </el-card>
  </div>
</template>

<style scoped>
.head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.rules {
  margin: 0;
  padding-left: 18px;
  color: #606266;
  line-height: 1.9;
}
</style>
