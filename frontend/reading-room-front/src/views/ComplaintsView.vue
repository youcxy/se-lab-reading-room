<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import http from '../api'
import { isManager, state } from '../store'

const list = ref([])
const loading = ref(false)
const filter = ref('')
const dialog = reactive({ visible: false, row: null, result: '' })
const form = reactive({ content: '' })

const statusText = { PENDING: '待处理', DONE: '已处理' }

async function load() {
  loading.value = true
  try {
    list.value = await http.get('/complaints', { params: filter.value ? { status: filter.value } : {} })
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}

async function create() {
  if (!form.content.trim()) {
    ElMessage.warning('请先填写投诉内容')
    return
  }
  try {
    await http.post('/complaints', { userId: state.user.id, content: form.content.trim() })
    ElMessage.success('投诉已提交，店长处理后会显示处理结果')
    form.content = ''
    await load()
  } catch (e) {
    ElMessage.error(e.message)
  }
}

function open(row) {
  dialog.row = row
  dialog.result = row.handleResult || ''
  dialog.visible = true
}

async function submitHandle() {
  if (!dialog.result.trim()) {
    ElMessage.warning('必须填写处理结果才能置为已处理')
    return
  }
  try {
    await http.post(`/complaints/${dialog.row.id}/handle`, {
      handlerId: state.user.id,
      result: dialog.result.trim()
    })
    ElMessage.success('已标记为已处理')
    dialog.visible = false
    await load()
  } catch (e) {
    ElMessage.error(e.message)
  }
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <el-card v-if="!isManager">
      <template #header>提交投诉</template>
      <el-input v-model="form.content" type="textarea" :rows="3" maxlength="200" show-word-limit
                placeholder="例如：A03 座位的台灯不亮" />
      <div class="actions">
        <el-button type="primary" @click="create">提交</el-button>
      </div>
      <el-alert type="info" :closable="false" style="margin-top: 8px"
                title="未填写处理结果时，店长不能把投诉置为“已处理”——这条规则在接口层校验。" />
    </el-card>

    <el-card style="margin-top: 12px">
      <template #header>
        <div class="head">
          <span>投诉列表</span>
          <div>
            <el-select v-model="filter" placeholder="全部状态" size="small" style="width: 140px" @change="load">
              <el-option label="全部" value="" />
              <el-option label="待处理" value="PENDING" />
              <el-option label="已处理" value="DONE" />
            </el-select>
            <el-button size="small" style="margin-left: 8px" @click="load">刷新</el-button>
          </div>
        </div>
      </template>

      <el-table :data="list" size="small" empty-text="暂无投诉">
        <el-table-column prop="id" label="编号" width="70" />
        <el-table-column prop="userName" label="提交人" width="110" />
        <el-table-column prop="content" label="投诉内容" min-width="220" show-overflow-tooltip />
        <el-table-column label="状态" width="100">
          <template #default="{ row }">
            <el-tag :type="row.status === 'DONE' ? 'success' : 'warning'" size="small">
              {{ statusText[row.status] || row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="handleResult" label="处理结果" min-width="220" show-overflow-tooltip />
        <el-table-column prop="handlerName" label="处理人" width="100" />
        <el-table-column prop="createdAt" label="提交时间" width="180" />
        <el-table-column v-if="isManager" label="操作" width="110" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="primary" :disabled="row.status === 'DONE'" @click="open(row)">
              {{ row.status === 'DONE' ? '已处理' : '处理' }}
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="dialog.visible" title="填写处理结果" width="520px">
      <p class="content">{{ dialog.row && dialog.row.content }}</p>
      <el-input v-model="dialog.result" type="textarea" :rows="3" placeholder="例如：已更换台灯并补偿 10 分钟" />
      <template #footer>
        <el-button @click="dialog.visible = false">取消</el-button>
        <el-button type="primary" @click="submitHandle">保存并置为已处理</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.actions {
  margin-top: 8px;
  text-align: right;
}
.content {
  color: #606266;
  background: #f5f7fa;
  padding: 8px 12px;
  border-radius: 4px;
}
</style>
