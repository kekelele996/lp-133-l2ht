<template>
  <div class="min-h-screen bg-gray-50">
    <div class="container mx-auto px-4 py-6">
      <h1 class="text-2xl font-bold text-gray-800 mb-6">我的订单</h1>

      <el-card class="mb-6">
        <el-tabs v-model="activeTab" @tab-change="fetchOrders">
          <el-tab-pane label="进行中" name="in_progress" />
          <el-tab-pane label="待确认" name="pending_confirm" />
          <el-tab-pane label="已完成" name="completed" />
          <el-tab-pane label="已评价" name="reviewed" />
          <el-tab-pane label="全部" name="" />
        </el-tabs>
      </el-card>

      <div v-if="loading" class="text-center py-16">
        <el-icon class="animate-spin text-4xl text-gray-400"><Loading /></el-icon>
      </div>

      <div v-else-if="orders.length === 0" class="text-center py-16">
        <el-icon class="text-6xl text-gray-300"><Document /></el-icon>
        <p class="mt-4 text-gray-500">暂无订单</p>
      </div>

      <div v-else class="space-y-4">
        <el-card v-for="order in orders" :key="order.id" class="hover:shadow-md">
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <div class="flex items-center mb-2">
                <h3 class="font-medium text-lg mr-3">{{ order.title }}</h3>
                <el-tag :type="getTypeColor(order.type)" size="small">
                  {{ getTypeName(order.type) }}
                </el-tag>
                <el-tag :type="getStatusTag(order).type" class="ml-2" size="small">
                  {{ getStatusTag(order).text }}
                </el-tag>
              </div>

              <div class="text-gray-600 text-sm mb-3">
                <p v-if="user?.role === 'volunteer'">
                  <el-icon class="mr-1"><User /></el-icon>
                  服务对象：{{ order.user_name }}
                </p>
                <p v-else>
                  <el-icon class="mr-1"><Service /></el-icon>
                  志愿者：{{ order.volunteer_name }}
                </p>
                <p class="mt-1">
                  <el-icon class="mr-1"><Location /></el-icon>
                  {{ order.address }}
                </p>
                <p v-if="order.service_hours" class="mt-1">
                  <el-icon class="mr-1"><Clock /></el-icon>
                  服务时长：{{ order.service_hours }} 小时
                </p>
                <p v-if="order.result" class="mt-1">
                  <el-icon class="mr-1"><Document /></el-icon>
                  服务结果：{{ order.result }}
                </p>
              </div>

              <div class="text-xs text-gray-400">
                下单时间：{{ new Date(order.created_at).toLocaleString() }}
              </div>
            </div>

            <div class="flex flex-col gap-2">
              <el-button
                v-if="order.status === 'in_progress' && user?.role === 'volunteer'"
                type="primary"
                size="small"
                @click="showFinishDialog(order)"
              >
                登记服务结果
              </el-button>
              <el-button
                v-if="order.status === 'pending_confirm' && user?.id === order.user_id"
                type="warning"
                size="small"
                @click="handleConfirm(order)"
              >
                确认完成
              </el-button>
              <el-tag
                v-if="order.status === 'pending_confirm' && user?.id === order.volunteer_id"
                type="warning"
                size="small"
              >
                等待居民确认
              </el-tag>
              <el-button
                v-if="order.status === 'completed' && !order.my_reviewed"
                type="success"
                size="small"
                @click="showReviewDialog(order)"
              >
                去评价
              </el-button>
              <el-button
                type="text"
                size="small"
                @click="handleMessage(order)"
              >
                <el-icon class="mr-1"><ChatDotRound /></el-icon>
                发消息
              </el-button>
            </div>
          </div>
        </el-card>
      </div>
    </div>

    <el-dialog v-model="finishDialogVisible" title="登记服务结果" width="500px">
      <el-form :model="finishForm" label-width="90px">
        <el-form-item label="服务时长">
          <el-input-number v-model="finishForm.service_hours" :min="0.5" :max="24" :step="0.5" />
          <span class="ml-2 text-gray-500">小时</span>
        </el-form-item>
        <el-form-item label="服务结果">
          <el-input
            v-model="finishForm.result"
            type="textarea"
            :rows="3"
            maxlength="500"
            placeholder="请简要说明服务完成情况，提交后由居民核对确认"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="finishDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submittingFinish" @click="submitFinish">提交登记</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="reviewDialogVisible" title="服务评价" width="500px">
      <el-form :model="reviewForm" label-width="80px">
        <el-form-item label="评分">
          <el-rate v-model="reviewForm.rating" :max="5" show-score />
        </el-form-item>
        <el-form-item label="评价内容">
          <el-input v-model="reviewForm.comment" type="textarea" :rows="3" placeholder="请输入评价内容" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="reviewDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submittingReview" @click="submitReview">提交评价</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import api from '@/utils/api'
import { ElMessage, ElMessageBox } from 'element-plus'

const router = useRouter()
const userStore = useUserStore()
const user = computed(() => userStore.user)

const orders = ref([])
const loading = ref(false)
const activeTab = ref('in_progress')
const finishDialogVisible = ref(false)
const submittingFinish = ref(false)
const reviewDialogVisible = ref(false)
const submittingReview = ref(false)
const currentOrder = ref(null)

const finishForm = ref({
  service_hours: 1,
  result: ''
})

const reviewForm = ref({
  rating: 5,
  comment: ''
})

const typeMap = {
  accompany: { name: '陪聊陪诊', color: 'blue' },
  shopping: { name: '代买代办', color: 'green' },
  repair: { name: '家电维修', color: 'orange' },
  housework: { name: '家政服务', color: 'purple' },
  other: { name: '其他帮助', color: 'gray' }
}

const getTypeName = (type) => typeMap[type]?.name || type
const getTypeColor = (type) => typeMap[type]?.color || 'info'

const getStatusTag = (order) => {
  if (order.status === 'in_progress') return { text: '进行中', type: 'warning' }
  if (order.status === 'pending_confirm') return { text: '待确认', type: 'primary' }
  if (order.status === 'completed') {
    return order.my_reviewed
      ? { text: '已评价', type: 'info' }
      : { text: '已完成', type: 'success' }
  }
  if (order.status === 'cancelled') return { text: '已取消', type: 'info' }
  return { text: order.status, type: 'info' }
}

const fetchOrders = async () => {
  loading.value = true
  try {
    const params = activeTab.value ? { status: activeTab.value } : {}
    const res = await api.get('/orders', { params })
    orders.value = res.data.orders
  } finally {
    loading.value = false
  }
}

const showFinishDialog = (order) => {
  currentOrder.value = order
  finishForm.value = { service_hours: 1, result: '' }
  finishDialogVisible.value = true
}

const submitFinish = async () => {
  if (!finishForm.value.result.trim()) {
    ElMessage.warning('请填写服务结果说明')
    return
  }
  try {
    submittingFinish.value = true
    await api.put(`/orders/${currentOrder.value.id}/finish`, {
      service_hours: finishForm.value.service_hours,
      result: finishForm.value.result.trim()
    })
    ElMessage.success('服务结果已登记，待居民确认')
    finishDialogVisible.value = false
    fetchOrders()
  } catch (e) {
    // 错误提示由拦截器统一弹出，刷新列表以同步最新状态
    fetchOrders()
  } finally {
    submittingFinish.value = false
  }
}

const handleConfirm = async (order) => {
  try {
    await ElMessageBox.confirm(
      `志愿者登记服务时长 ${order.service_hours} 小时，服务结果：${order.result || '无'}。确认无误后订单完成，积分与时长将结算给志愿者。`,
      '确认完成',
      {
        confirmButtonText: '确认完成',
        cancelButtonText: '再想想',
        type: 'warning'
      }
    )

    await api.put(`/orders/${order.id}/confirm`)
    ElMessage.success('已确认完成')
    fetchOrders()
    userStore.fetchUserInfo()
  } catch (e) {
    if (e !== 'cancel') {
      fetchOrders()
    }
  }
}

const showReviewDialog = (order) => {
  currentOrder.value = order
  reviewForm.value = { rating: 5, comment: '' }
  reviewDialogVisible.value = true
}

const submitReview = async () => {
  try {
    submittingReview.value = true
    await api.post(`/orders/${currentOrder.value.id}/review`, reviewForm.value)
    ElMessage.success('评价成功')
    reviewDialogVisible.value = false
    fetchOrders()
  } catch (e) {
    fetchOrders()
  } finally {
    submittingReview.value = false
  }
}

const handleMessage = (order) => {
  const otherUserId = user.value.role === 'volunteer' ? order.user_id : order.volunteer_id
  router.push({
    path: '/messages',
    query: { userId: otherUserId }
  })
}

onMounted(() => {
  fetchOrders()
})
</script>
