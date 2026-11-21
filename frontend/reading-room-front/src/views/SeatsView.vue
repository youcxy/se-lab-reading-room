<script setup>
import { computed, onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import http from '../api'
import { refreshUser, state, statusText } from '../store'

const room = ref({ name: '', seatCount: 0, basePrice: 0, currentPrice: 0 })
const seats = ref([])
const mine = ref([])
const loading = ref(false)
const busy = ref(0)

const occupied = computed(() => seats.value.filter((s) => s.status !== 'FREE').length)
const rate = computed(() => (seats.value.length ? occupied.value / seats.value.length : 0))

const activeBySeat = computed(() => {
  const map = {}
  mine.value
    .filter((r) => ['RESERVED', 'IN_USE', 'TEMP_LEAVE'].includes(r.status))
    .forEach((r) => {
      map[r.seatId] = r
    })
  return map
})

function seatType(seat) {
  if (seat.status === 'FREE') return 'success'
  if (seat.status === 'RESERVED') return 'warning'
  if (seat.status === 'TEMP_LEAVE') return 'info'
  return 'danger'
}

async function load() {
  loading.value = true
  try {
    const [roomData, seatData] = await Promise.all([http.get('/room'), http.get('/seats')])
    room.value = roomData
    seats.value = seatData
    if (state.user) {
      mine.value = await http.get('/reservations', { params: { userId: state.user.id } })
      await refreshUser()
    }
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}

async function act(seat, action, okText) {
  const active = activeBySeat.value[seat.id]
  busy.value = seat.id
  try {
    if (action === 'reserve') {
      await http.post(`/seats/${seat.id}/reserve`, { userId: state.user.id })
    } else {
      await http.post(`/reservations/${active.id}/${action}`, { userId: state.user.id })
    }
    ElMessage.success(okText)
    await load()
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    busy.value = 0
  }
}

async function checkout(seat) {
  const active = activeBySeat.value[seat.id]
  busy.value = seat.id
  try {
    const bill = await http.post(`/reservations/${active.id}/checkout`, { userId: state.user.id })
    await ElMessageBox.alert(
      `本次使用 ${bill.minutes} 分钟，单价 ${bill.unitPrice} 元/小时，合计 ${bill.amount} 元` +
        `（来源：${bill.source === 'CLOUD' ? '华为云函数工作流计算' : '本地兜底计算'}，券类型 ${bill.cardType}）`,
      '签退成功',
      { confirmButtonText: '知道了' }
    )
    await load()
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    busy.value = 0
  }
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <el-card class="summary">
      <div class="row">
        <span class="room">{{ room.name }}</span>
        <el-tag>座位占用 {{ occupied }} / {{ seats.length }}</el-tag>
        <el-tag type="success">上座率 {{ (rate * 100).toFixed(0) }}%</el-tag>
        <el-tag type="warning">当前单价 {{ room.currentPrice }} 元/小时</el-tag>
        <el-tag type="info">基准单价 {{ room.basePrice }} 元/小时</el-tag>
        <span class="hint">预约后 15 分钟内未签到会释放座位、信用 -10 并扣 1 小时单价违约金</span>
      </div>
    </el-card>

    <el-row :gutter="12" class="seat-row">
      <el-col v-for="seat in seats" :key="seat.id" :xs="12" :sm="8" :md="6" :lg="4">
        <el-card :class="['seat', seat.status.toLowerCase()]" shadow="hover">
          <div class="seat-head">
            <span class="code">{{ seat.code }}</span>
            <el-tag :type="seatType(seat)" size="small">{{ statusText(seat.status) }}</el-tag>
          </div>
          <div class="seat-owner">
            <template v-if="seat.currentUserId">
              {{ seat.currentUserId === state.user.id ? '我' : seat.currentUserName }}
              <el-tag v-if="seat.leaveFlag" type="info" size="small" effect="dark">暂离</el-tag>
            </template>
            <template v-else>—</template>
          </div>

          <div class="seat-actions">
            <template v-if="seat.status === 'FREE'">
              <el-button
                type="primary"
                size="small"
                :disabled="state.user.credit < 60 || busy === seat.id"
                @click="act(seat, 'reserve', '预约成功，15 分钟内签到')"
              >
                预约
              </el-button>
            </template>

            <template v-else-if="activeBySeat[seat.id]">
              <el-button
                v-if="activeBySeat[seat.id].status === 'RESERVED'"
                type="success"
                size="small"
                :loading="busy === seat.id"
                @click="act(seat, 'checkin', '签到成功')"
              >
                签到
              </el-button>
              <template v-if="activeBySeat[seat.id].status === 'IN_USE'">
                <el-button size="small" :loading="busy === seat.id" @click="act(seat, 'leave', '已暂离，座位仍占用')">
                  暂离
                </el-button>
                <el-button type="warning" size="small" :loading="busy === seat.id" @click="checkout(seat)">签退</el-button>
              </template>
              <template v-if="activeBySeat[seat.id].status === 'TEMP_LEAVE'">
                <el-button size="small" :loading="busy === seat.id" @click="act(seat, 'end-leave', '已结束暂离')">
                  结束暂离
                </el-button>
                <el-button type="warning" size="small" :loading="busy === seat.id" @click="checkout(seat)">签退</el-button>
              </template>
            </template>

            <span v-else class="taken">他人使用中</span>
          </div>
        </el-card>
      </el-col>
    </el-row>

    <el-card class="balance">
      <span>我的信用分：<b>{{ state.user && state.user.credit }}</b></span>
      <el-divider direction="vertical" />
      <span>余额：<b>{{ state.user && state.user.balance }}</b> 元</span>
      <el-divider direction="vertical" />
      <span v-if="state.user && state.user.monthlyExpireDate">月卡到期：{{ state.user.monthlyExpireDate }}</span>
      <span v-else-if="state.user && state.user.dayPassDate">包天卡日期：{{ state.user.dayPassDate }}</span>
      <span v-else>无有效卡券（按分钟计费）</span>
      <span v-if="state.user && state.user.credit < 60" class="warn">信用低于 60，不能预约座位</span>
    </el-card>
  </div>
</template>

<style scoped>
.summary .row {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.room {
  font-size: 18px;
  font-weight: 700;
  margin-right: 8px;
}
.hint {
  color: #909399;
  font-size: 12px;
}
.seat-row {
  margin-top: 4px;
}
.seat {
  margin-bottom: 12px;
  border-top: 4px solid #67c23a;
}
.seat.reserved {
  border-top-color: #e6a23c;
}
.seat.in_use {
  border-top-color: #f56c6c;
}
.seat.temp_leave {
  border-top-color: #909399;
}
.seat-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.code {
  font-size: 20px;
  font-weight: 700;
}
.seat-owner {
  color: #606266;
  font-size: 13px;
  min-height: 22px;
  margin: 6px 0 10px;
}
.seat-actions {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
  min-height: 32px;
}
.seat-actions .el-button {
  margin-left: 0;
}
.taken {
  color: #909399;
  font-size: 12px;
}
.balance {
  margin-top: 4px;
  color: #606266;
}
.warn {
  color: #f56c6c;
  margin-left: 12px;
}
</style>
