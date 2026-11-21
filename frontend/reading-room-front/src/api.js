import axios from 'axios'

// 后端统一返回 { code, message, data }，code=0 表示成功；这里把 data 直接交给页面。
const http = axios.create({ baseURL: '/api', timeout: 20000 })

http.interceptors.response.use(
  (response) => {
    const body = response.data
    if (body && typeof body === 'object' && 'code' in body) {
      if (body.code !== 0) {
        return Promise.reject(new Error(body.message || '请求失败'))
      }
      return body.data
    }
    return body
  },
  (error) => {
    const data = error.response && error.response.data
    const message = (data && data.message) || error.message || '网络异常'
    return Promise.reject(new Error(message))
  }
)

export default http
