import { computed, reactive } from 'vue'
import http from './api'

const STORAGE_KEY = 'studyroom.user'

function read() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? JSON.parse(raw) : null
  } catch (e) {
    return null
  }
}

export const state = reactive({
  user: read(),
  businessTime: ''
})

export function setUser(user) {
  state.user = user
  localStorage.setItem(STORAGE_KEY, JSON.stringify(user))
}

export function logout() {
  state.user = null
  localStorage.removeItem(STORAGE_KEY)
}

export const isManager = computed(
  () => !!state.user && (state.user.role === 'MANAGER' || state.user.role === 'ADMIN')
)

export const isMember = computed(() => !!state.user && state.user.role === 'MEMBER')

/** 重新拉一次本人信息，保证信用分、余额是最新的。 */
export async function refreshUser() {
  if (!state.user) return null
  const users = await http.get('/users')
  const me = users.find((u) => u.id === state.user.id)
  if (me) setUser(me)
  return me
}

export async function refreshClock() {
  const clock = await http.get('/clock')
  state.businessTime = clock.businessTime
  return clock
}

export function statusText(status) {
  return (
    {
      FREE: '空闲',
      RESERVED: '已预约',
      IN_USE: '使用中',
      TEMP_LEAVE: '暂离中',
      MAINTENANCE: '维护'
    }[status] || status
  )
}
