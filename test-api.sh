#!/bin/bash

echo "======================================"
echo "  志愿者互助平台 - API 全流程测试"
echo "======================================"
echo ""

BASE_URL="http://localhost:3233/api"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 全局变量
VOLUNTEER_TOKEN=""
VOLUNTEER2_TOKEN=""
RESIDENT_TOKEN=""
VOLUNTEER_ID=""
RESIDENT_ID=""
NEED_ID=""
ORDER_ID=""
INITIAL_POINTS=0

test_step() {
  echo -e "${YELLOW}▶ $1${NC}"
}

test_pass() {
  echo -e "${GREEN}  ✓ $1${NC}"
}

test_fail() {
  echo -e "${RED}  ✗ $1${NC}"
  exit 1
}

json_field() {
  python3 -c "import sys,json; print(json.load(sys.stdin)$1)"
}

# 按需求ID精确查找订单（created_at 精度为秒，不能依赖列表顺序）
order_id_by_need() {
  curl -s "$BASE_URL/orders" -H "Authorization: Bearer $VOLUNTEER_TOKEN" | \
    python3 -c "import sys,json; print([o for o in json.load(sys.stdin)['orders'] if o['need_id']==$1][0]['id'])"
}

# 1. 测试健康检查
test_step "1. 健康检查"
HEALTH_RES=$(curl -s "$BASE_URL/health")
if echo "$HEALTH_RES" | grep -q "ok" > /dev/null 2>&1; then
  test_pass "后端服务正常 - $(echo $HEALTH_RES | json_field "['message']")"
else
  test_fail "后端服务未启动，请先运行 ./start-all.sh"
fi

echo ""

# 2. 测试登录 - 居民
test_step "2. 居民登录 (13900139001 / 123456)"
LOGIN_RES=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13900139001","password":"123456"}')

if echo "$LOGIN_RES" | grep -q "登录成功" > /dev/null 2>&1; then
  RESIDENT_TOKEN=$(echo "$LOGIN_RES" | json_field "['token']")
  RESIDENT_ID=$(echo "$LOGIN_RES" | json_field "['user']['id']")
  test_pass "居民登录成功，ID: $RESIDENT_ID"
else
  echo "响应: $LOGIN_RES"
  test_fail "居民登录失败"
fi

echo ""

# 3. 测试登录 - 志愿者
test_step "3. 志愿者登录 (13800138001 / 123456)"
LOGIN_RES=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13800138001","password":"123456"}')

if echo "$LOGIN_RES" | grep -q "登录成功" > /dev/null 2>&1; then
  VOLUNTEER_TOKEN=$(echo "$LOGIN_RES" | json_field "['token']")
  VOLUNTEER_ID=$(echo "$LOGIN_RES" | json_field "['user']['id']")
  INITIAL_POINTS=$(echo "$LOGIN_RES" | json_field "['user']['points']")
  test_pass "志愿者登录成功，ID: $VOLUNTEER_ID, 初始积分: $INITIAL_POINTS"
else
  echo "响应: $LOGIN_RES"
  test_fail "志愿者登录失败"
fi

echo ""

# 3b. 第二个志愿者登录（用于非参与人评价测试）
test_step "3b. 志愿者2登录 (13800138002 / 123456)"
LOGIN_RES=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13800138002","password":"123456"}')

if echo "$LOGIN_RES" | grep -q "登录成功" > /dev/null 2>&1; then
  VOLUNTEER2_TOKEN=$(echo "$LOGIN_RES" | json_field "['token']")
  test_pass "志愿者2登录成功"
else
  echo "响应: $LOGIN_RES"
  test_fail "志愿者2登录失败"
fi

echo ""

# 4. 测试获取礼品列表
test_step "4. 获取礼品列表"
GIFTS_RES=$(curl -s "$BASE_URL/gifts")
if echo "$GIFTS_RES" | grep -q "保温杯" > /dev/null 2>&1; then
  GIFT_COUNT=$(echo "$GIFTS_RES" | json_field "['gifts'].__len__()")
  FIRST_GIFT=$(echo "$GIFTS_RES" | python3 -c "import sys,json; g=json.load(sys.stdin)['gifts'][0]; print(f'{g[\"name\"]} ({g[\"points_required\"]}积分)')")
  test_pass "获取到 $GIFT_COUNT 个礼品，第一个: $FIRST_GIFT"
else
  echo "响应: $GIFTS_RES"
  test_fail "获取礼品列表失败"
fi

echo ""

# 5. 测试发布需求
test_step "5. 居民发布需求"
PUBLISH_RES=$(curl -s -X POST "$BASE_URL/needs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{
    "title": "需要帮忙买 groceries",
    "description": "腿脚不方便，需要帮忙去超市买些生活用品",
    "type": "shopping",
    "address": "北京市朝阳区光华路2号",
    "lat": 39.9122,
    "lng": 116.4574,
    "expected_time": "2026-05-20 10:00:00"
  }')

if echo "$PUBLISH_RES" | grep -q "发布成功" > /dev/null 2>&1; then
  NEED_ID=$(echo "$PUBLISH_RES" | json_field "['needId']")
  test_pass "需求发布成功，需求ID: $NEED_ID"
else
  echo "响应: $PUBLISH_RES"
  test_fail "发布需求失败"
fi

echo ""

# 6. 测试获取需求列表
test_step "6. 获取需求列表"
NEEDS_RES=$(curl -s "$BASE_URL/needs?pageSize=10")
if echo "$NEEDS_RES" | grep -q "needs" > /dev/null 2>&1; then
  NEED_COUNT=$(echo "$NEEDS_RES" | json_field "['needs'].__len__()")
  test_pass "获取到 $NEED_COUNT 条需求"
else
  test_fail "获取需求列表失败"
fi

echo ""

# 7. 测试志愿者接单
test_step "7. 志愿者接单"
ACCEPT_RES=$(curl -s -X POST "$BASE_URL/needs/$NEED_ID/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$ACCEPT_RES" | grep -q "接单成功" > /dev/null 2>&1; then
  test_pass "接单成功"
else
  echo "响应: $ACCEPT_RES"
  test_fail "接单失败"
fi

echo ""

# 8. 测试获取订单列表
test_step "8. 获取订单列表"
ORDERS_RES=$(curl -s "$BASE_URL/orders" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$ORDERS_RES" | grep -q "orders" > /dev/null 2>&1; then
  ORDER_ID=$(order_id_by_need $NEED_ID)
  test_pass "获取订单成功，订单ID: $ORDER_ID"
else
  echo "响应: $ORDERS_RES"
  test_fail "获取订单列表失败"
fi

echo ""

# 9. 志愿者登记服务结果（订单进入待确认，不结算积分）
test_step "9. 志愿者登记服务结果 (服务时长 2 小时)"
REPORT_RES=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/report" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"service_hours": 2, "service_result": "已陪同超市采购完毕"}')

if echo "$REPORT_RES" | grep -q "等待居民确认" > /dev/null 2>&1; then
  ORDER_STATUS=$(curl -s "$BASE_URL/orders?status=pending_confirm" \
    -H "Authorization: Bearer $VOLUNTEER_TOKEN" | python3 -c "import sys,json; print([o for o in json.load(sys.stdin)['orders'] if o['id']==$ORDER_ID][0]['status'])")
  test_pass "登记成功，订单进入待确认状态 (status=$ORDER_STATUS)"
else
  echo "响应: $REPORT_RES"
  test_fail "登记服务结果失败"
fi

echo ""

# 10. 重复登记必须失败（不能改掉已确定结果）
test_step "10. 重复登记服务结果（应失败）"
REPORT_AGAIN=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/report" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"service_hours": 5, "service_result": "试图篡改时长"}')

if echo "$REPORT_AGAIN" | grep -q "无法登记服务结果" > /dev/null 2>&1; then
  HOURS_NOW=$(curl -s "$BASE_URL/orders" \
    -H "Authorization: Bearer $VOLUNTEER_TOKEN" | python3 -c "import sys,json; print([o for o in json.load(sys.stdin)['orders'] if o['id']==$ORDER_ID][0]['service_hours'])")
  if [ "$HOURS_NOW" = "2.00" ]; then
    test_pass "重复登记被拒绝，已登记的时长未被篡改 (仍为 $HOURS_NOW 小时)"
  else
    test_fail "重复登记被拒绝，但时长被篡改: $HOURS_NOW"
  fi
else
  echo "响应: $REPORT_AGAIN"
  test_fail "重复登记未被拒绝"
fi

echo ""

# 11. 居民确认前积分不结算
test_step "11. 确认前志愿者积分未结算"
POINTS_BEFORE=$(curl -s "$BASE_URL/user/profile" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" | json_field "['user']['points']")
if [ "$POINTS_BEFORE" = "$INITIAL_POINTS" ]; then
  test_pass "积分未提前结算: $POINTS_BEFORE"
else
  test_fail "积分被提前结算: $POINTS_BEFORE (初始 $INITIAL_POINTS)"
fi

echo ""

# 12. 志愿者不能自己确认订单
test_step "12. 志愿者尝试确认订单（应失败）"
CONFIRM_BY_VOL=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$CONFIRM_BY_VOL" | grep -q "只有需求发布者可以确认完成" > /dev/null 2>&1; then
  test_pass "志愿者确认被明确拒绝"
else
  echo "响应: $CONFIRM_BY_VOL"
  test_fail "志愿者确认未被拒绝"
fi

echo ""

# 13. 居民确认完成（订单与需求收口，积分结算）
test_step "13. 居民确认完成"
CONFIRM_RES=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN")

if echo "$CONFIRM_RES" | grep -q "已确认完成" > /dev/null 2>&1; then
  NEED_STATUS=$(curl -s "$BASE_URL/needs/$NEED_ID" | json_field "['need']['status']")
  test_pass "订单确认完成，需求状态: $NEED_STATUS"
  if [ "$NEED_STATUS" != "completed" ]; then
    test_fail "需求未同步收口"
  fi
else
  echo "响应: $CONFIRM_RES"
  test_fail "居民确认失败"
fi

echo ""

# 14. 重复确认必须失败，且积分不重复结算
test_step "14. 重复确认（应失败且不重复结算）"
CONFIRM_AGAIN=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN")

POINTS_AFTER=$(curl -s "$BASE_URL/user/profile" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" | json_field "['user']['points']")
EXPECTED_POINTS=$((INITIAL_POINTS + 20))

if echo "$CONFIRM_AGAIN" | grep -q "请勿重复操作" > /dev/null 2>&1 && [ "$POINTS_AFTER" = "$EXPECTED_POINTS" ]; then
  test_pass "重复确认被拒绝，积分只结算一次: $POINTS_AFTER (原 $INITIAL_POINTS + 2小时×10)"
else
  echo "响应: $CONFIRM_AGAIN, 积分: $POINTS_AFTER (预期 $EXPECTED_POINTS)"
  test_fail "重复确认校验失败"
fi

echo ""

# 15. 居民评价订单
test_step "15. 居民评价订单"
REVIEW_RES=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"rating": 5, "comment": "志愿者非常热心，服务很好！"}')

if echo "$REVIEW_RES" | grep -q "评价成功" > /dev/null 2>&1; then
  test_pass "居民评价成功"
else
  echo "响应: $REVIEW_RES"
  test_fail "居民评价失败"
fi

echo ""

# 16. 重复评价必须失败
test_step "16. 居民重复评价（应失败）"
REVIEW_AGAIN=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"rating": 1, "comment": "试图重复评价"}')

if echo "$REVIEW_AGAIN" | grep -q "请勿重复评价" > /dev/null 2>&1; then
  test_pass "重复评价被明确拒绝"
else
  echo "响应: $REVIEW_AGAIN"
  test_fail "重复评价未被拒绝"
fi

echo ""

# 17. 志愿者评价订单
test_step "17. 志愿者评价订单"
REVIEW_RES2=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"rating": 5, "comment": "居民很友善，合作愉快！"}')

if echo "$REVIEW_RES2" | grep -q "评价成功" > /dev/null 2>&1; then
  test_pass "志愿者评价成功"
else
  echo "响应: $REVIEW_RES2"
  test_fail "志愿者评价失败"
fi

echo ""

# 18. 非参与人评价必须失败
test_step "18. 非参与人评价（应失败）"
REVIEW_OUTSIDER=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER2_TOKEN" \
  -d '{"rating": 5, "comment": "路人评价"}')

if echo "$REVIEW_OUTSIDER" | grep -q "只有订单参与者可以评价" > /dev/null 2>&1; then
  test_pass "非参与人评价被明确拒绝"
else
  echo "响应: $REVIEW_OUTSIDER"
  test_fail "非参与人评价未被拒绝"
fi

echo ""

# 19. 未完成订单评价必须失败
test_step "19. 未完成订单评价（应失败）"
PUBLISH_RES2=$(curl -s -X POST "$BASE_URL/needs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"title":"需要陪同散步","description":"下午想找人陪同散步","type":"accompany","address":"北京市朝阳区光华路2号","lat":39.9122,"lng":116.4574}')
NEED_ID_2=$(echo "$PUBLISH_RES2" | json_field "['needId']")
curl -s -X POST "$BASE_URL/needs/$NEED_ID_2/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" > /dev/null
ORDER_ID_2=$(order_id_by_need $NEED_ID_2)

REVIEW_UNFINISHED=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID_2/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"rating": 5, "comment": "还没完成就评价"}')

if echo "$REVIEW_UNFINISHED" | grep -q "订单未完成" > /dev/null 2>&1; then
  test_pass "未完成订单评价被明确拒绝"
else
  echo "响应: $REVIEW_UNFINISHED"
  test_fail "未完成订单评价未被拒绝"
fi

echo ""

# 20. 并发确认：两个确认请求同时到达，只有一个生效
test_step "20. 并发确认（撞单只结算一次）"
PUBLISH_RES3=$(curl -s -X POST "$BASE_URL/needs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"title":"帮忙取快递","description":"快递在驿站，需要帮忙取","type":"shopping","address":"北京市朝阳区光华路2号","lat":39.9122,"lng":116.4574}')
NEED_ID_3=$(echo "$PUBLISH_RES3" | json_field "['needId']")
curl -s -X POST "$BASE_URL/needs/$NEED_ID_3/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" > /dev/null
ORDER_ID_3=$(order_id_by_need $NEED_ID_3)
curl -s -X PUT "$BASE_URL/orders/$ORDER_ID_3/report" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"service_hours": 1, "service_result": "快递已送达"}' > /dev/null

RACE_A=$(mktemp); RACE_B=$(mktemp)
curl -s -X PUT "$BASE_URL/orders/$ORDER_ID_3/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" > "$RACE_A" &
curl -s -X PUT "$BASE_URL/orders/$ORDER_ID_3/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" > "$RACE_B" &
wait

SUCCESS_COUNT=$(grep -l "已确认完成" "$RACE_A" "$RACE_B" | wc -l)
POINTS_RACE=$(curl -s "$BASE_URL/user/profile" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" | json_field "['user']['points']")
EXPECTED_RACE=$((EXPECTED_POINTS + 10))
rm -f "$RACE_A" "$RACE_B"

if [ "$SUCCESS_COUNT" = "1" ] && [ "$POINTS_RACE" = "$EXPECTED_RACE" ]; then
  test_pass "并发确认仅一个生效，积分只结算一次: $POINTS_RACE (+1小时×10)"
else
  test_fail "并发确认异常: 成功数=$SUCCESS_COUNT, 积分=$POINTS_RACE (预期 $EXPECTED_RACE)"
fi

echo ""

# 21. 测试兑换礼品
test_step "21. 志愿者兑换礼品 (保温杯 100 积分)"
GIFT_ID=1
EXCHANGE_RES=$(curl -s -X POST "$BASE_URL/gifts/$GIFT_ID/exchange" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$EXCHANGE_RES" | grep -q "兑换成功" > /dev/null 2>&1; then
  test_pass "礼品兑换成功"
else
  echo "响应: $EXCHANGE_RES"
  test_fail "兑换礼品失败"
fi

echo ""

# 22. 测试获取兑换记录
test_step "22. 获取兑换记录"
EXCHANGES_RES=$(curl -s "$BASE_URL/my/exchanges" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$EXCHANGES_RES" | grep -q "exchanges" > /dev/null 2>&1; then
  EX_COUNT=$(echo "$EXCHANGES_RES" | json_field "['exchanges'].__len__()")
  EX_GIFT=$(echo "$EXCHANGES_RES" | python3 -c "import sys,json; e=json.load(sys.stdin)['exchanges'][0]; print(f'{e[\"name\"]} ({e[\"points\"]}积分)')")
  test_pass "获取到 $EX_COUNT 条兑换记录，最新: $EX_GIFT"
else
  echo "响应: $EXCHANGES_RES"
  test_fail "获取兑换记录失败"
fi

echo ""

# 23. 测试发送消息
test_step "23. 发送消息"
MSG_RES=$(curl -s -X POST "$BASE_URL/messages" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d "{\"receiver_id\": $RESIDENT_ID, \"content\": \"您好，我是志愿者，请问明天上午10点可以吗？\"}")

if echo "$MSG_RES" | grep -q "发送成功" > /dev/null 2>&1; then
  test_pass "消息发送成功"
else
  echo "响应: $MSG_RES"
  test_fail "发送消息失败"
fi

echo ""

# 24. 测试获取消息列表
test_step "24. 获取消息列表"
MSGS_RES=$(curl -s "$BASE_URL/messages?other_user_id=$VOLUNTEER_ID" \
  -H "Authorization: Bearer $RESIDENT_TOKEN")

if echo "$MSGS_RES" | grep -q "messages" > /dev/null 2>&1; then
  MSG_COUNT=$(echo "$MSGS_RES" | json_field "['messages'].__len__()")
  test_pass "获取到 $MSG_COUNT 条消息"
else
  echo "响应: $MSGS_RES"
  test_fail "获取消息列表失败"
fi

echo ""

# 25. 测试积分排名
test_step "25. 获取志愿者排名"
RANKING_RES=$(curl -s "$BASE_URL/users/ranking")
if echo "$RANKING_RES" | grep -q "ranking" > /dev/null 2>&1; then
  RANK_COUNT=$(echo "$RANKING_RES" | json_field "['ranking'].__len__()")
  TOP_NAME=$(echo "$RANKING_RES" | json_field "['ranking'][0]['name']")
  test_pass "获取到 $RANK_COUNT 名志愿者排名，第一名: $TOP_NAME"
else
  echo "响应: $RANKING_RES"
  test_fail "获取排名失败"
fi

echo ""
echo "======================================"
echo -e "${GREEN}🎉 所有测试通过！${NC}"
echo "======================================"
echo ""
echo "📋 测试总结："
echo "   ✅ 后端健康检查"
echo "   ✅ 用户登录（居民 + 志愿者）"
echo "   ✅ 礼品列表查询"
echo "   ✅ 发布需求 / 需求列表 / 接单"
echo "   ✅ 志愿者登记服务结果 → 订单待确认"
echo "   ✅ 重复登记被拒绝且不篡改结果"
echo "   ✅ 确认前积分不结算"
echo "   ✅ 志愿者无权确认订单"
echo "   ✅ 居民确认完成 → 订单与需求收口"
echo "   ✅ 重复确认被拒绝，积分只结算一次（2小时=20积分）"
echo "   ✅ 双方各评价一次，重复评价被拒绝"
echo "   ✅ 非参与人 / 未完成订单评价被拒绝"
echo "   ✅ 并发确认撞单只生效一次"
echo "   ✅ 积分兑换礼品 / 兑换记录"
echo "   ✅ 消息发送/接收"
echo "   ✅ 积分排名"
echo ""
echo "🎮 现在可以打开浏览器访问 http://localhost:8233 体验完整功能"
echo ""
