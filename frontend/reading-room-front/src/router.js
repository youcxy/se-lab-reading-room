import { createRouter, createWebHashHistory } from 'vue-router'
import { state } from './store'
import LoginView from './views/LoginView.vue'
import SeatsView from './views/SeatsView.vue'
import MyView from './views/MyView.vue'
import ComplaintsView from './views/ComplaintsView.vue'
import DashboardView from './views/DashboardView.vue'
import PricingView from './views/PricingView.vue'

const routes = [
  { path: '/', redirect: '/seats' },
  { path: '/login', component: LoginView, meta: { public: true } },
  { path: '/seats', component: SeatsView },
  { path: '/me', component: MyView },
  { path: '/complaints', component: ComplaintsView },
  { path: '/dashboard', component: DashboardView },
  { path: '/pricing', component: PricingView }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach((to) => {
  if (!to.meta.public && !state.user) {
    return { path: '/login' }
  }
  if (to.path === '/login' && state.user) {
    return { path: '/seats' }
  }
  return true
})

export default router
