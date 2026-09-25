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
RESIDENT_TOKEN=""
OTHER_TOKEN=""
VOLUNTEER_ID=""
RESIDENT_ID=""
NEED_ID=""
ORDER_ID=""
ORDER_ID_2=""
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

# 1. 测试健康检查
test_step "1. 健康检查"
HEALTH_RES=$(curl -s "$BASE_URL/health")
if echo "$HEALTH_RES" | grep -q "ok" > /dev/null 2>&1; then
  test_pass "后端服务正常 - $(echo $HEALTH_RES | python3 -c "import sys,json; print(json.load(sys.stdin)['message'])")"
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
  RESIDENT_TOKEN=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  RESIDENT_ID=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])")
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
  VOLUNTEER_TOKEN=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  VOLUNTEER_ID=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])")
  INITIAL_POINTS=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")
  test_pass "志愿者登录成功，ID: $VOLUNTEER_ID, 初始积分: $INITIAL_POINTS"
else
  echo "响应: $LOGIN_RES"
  test_fail "志愿者登录失败"
fi

echo ""

# 4. 测试获取礼品列表
test_step "4. 获取礼品列表"
GIFTS_RES=$(curl -s "$BASE_URL/gifts")
if echo "$GIFTS_RES" | grep -q "保温杯" > /dev/null 2>&1; then
  GIFT_COUNT=$(echo "$GIFTS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['gifts']))")
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
  NEED_ID=$(echo "$PUBLISH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['needId'])")
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
  NEED_COUNT=$(echo "$NEEDS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['needs']))")
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
  ORDER_ID=$(echo "$ORDERS_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['orders'][0]['id'])")
  test_pass "获取订单成功，订单ID: $ORDER_ID"
else
  echo "响应: $ORDERS_RES"
  test_fail "获取订单列表失败"
fi

echo ""

# 9. 志愿者登记服务结果（时长+结果），订单进入待确认
test_step "9. 志愿者登记服务结果 (服务时长 2 小时)"
FINISH_RES=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/finish" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"service_hours": 2, "result": "已代买生活用品并送到家中"}')

if echo "$FINISH_RES" | grep -q "待居民确认" > /dev/null 2>&1; then
  test_pass "服务结果登记成功，订单进入待确认"
else
  echo "响应: $FINISH_RES"
  test_fail "登记服务结果失败"
fi

echo ""

# 10. 重复登记应失败（订单已不在进行中）
test_step "10. 重复登记服务结果应失败"
FINISH_AGAIN=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/finish" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"service_hours": 5, "result": "重复提交尝试篡改时长"}')

if echo "$FINISH_AGAIN" | grep -q "状态已变更" > /dev/null 2>&1; then
  test_pass "重复登记被拒绝，已登记结果未被覆盖"
else
  echo "响应: $FINISH_AGAIN"
  test_fail "重复登记未被拒绝"
fi

echo ""

# 11. 居民确认前评价应失败（订单未完成）
test_step "11. 订单未完成时评价应失败"
EARLY_REVIEW=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"rating": 5, "comment": "提前评价"}')

if echo "$EARLY_REVIEW" | grep -q "不能评价" > /dev/null 2>&1; then
  test_pass "未完成订单评价被拒绝"
else
  echo "响应: $EARLY_REVIEW"
  test_fail "未完成订单评价未被拒绝"
fi

echo ""

# 12. 志愿者不能替居民确认
test_step "12. 志愿者确认订单应失败（仅居民可确认）"
VOL_CONFIRM=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$VOL_CONFIRM" | grep -q "仅需求发布人" > /dev/null 2>&1; then
  test_pass "志愿者确认被拒绝"
else
  echo "响应: $VOL_CONFIRM"
  test_fail "志愿者确认未被拒绝"
fi

echo ""

# 13. 居民确认完成，积分与时长结算
test_step "13. 居民确认完成（结算积分与时长）"
CONFIRM_RES=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN")

if echo "$CONFIRM_RES" | grep -q "已确认完成" > /dev/null 2>&1; then
  test_pass "居民确认完成成功"
else
  echo "响应: $CONFIRM_RES"
  test_fail "居民确认完成失败"
fi

echo ""

# 14. 重复确认应失败，且积分不重复结算
test_step "14. 重复确认应失败且积分不重复结算"
CONFIRM_AGAIN=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN")

if echo "$CONFIRM_AGAIN" | grep -q "状态已变更" > /dev/null 2>&1; then
  PROFILE_RES=$(curl -s "$BASE_URL/user/profile" -H "Authorization: Bearer $VOLUNTEER_TOKEN")
  POINTS=$(echo "$PROFILE_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")
  EXPECTED_POINTS=$((INITIAL_POINTS + 20))
  if [ "$POINTS" = "$EXPECTED_POINTS" ]; then
    test_pass "重复确认被拒绝，积分仍只结算一次: $POINTS (原 $INITIAL_POINTS + 20)"
  else
    test_fail "积分被重复结算: $POINTS (预期 $EXPECTED_POINTS)"
  fi
else
  echo "响应: $CONFIRM_AGAIN"
  test_fail "重复确认未被拒绝"
fi

echo ""

# 15. 需求状态应已收口为 completed
test_step "15. 需求状态已收口"
NEED_RES=$(curl -s "$BASE_URL/needs/$NEED_ID")
NEED_STATUS=$(echo "$NEED_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['need']['status'])")
if [ "$NEED_STATUS" = "completed" ]; then
  test_pass "需求状态: $NEED_STATUS"
else
  test_fail "需求状态异常: $NEED_STATUS (预期 completed)"
fi

echo ""

# 16. 非参与人评价应失败
test_step "16. 非参与人评价应失败"
OTHER_LOGIN=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13900139002","password":"123456"}')
OTHER_TOKEN=$(echo "$OTHER_LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

OUTSIDER_REVIEW=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OTHER_TOKEN" \
  -d '{"rating": 1, "comment": "路人乱评"}')

if echo "$OUTSIDER_REVIEW" | grep -q "参与人" > /dev/null 2>&1; then
  test_pass "非参与人评价被拒绝"
else
  echo "响应: $OUTSIDER_REVIEW"
  test_fail "非参与人评价未被拒绝"
fi

echo ""

# 17. 居民评价订单
test_step "17. 居民评价订单"
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

# 18. 重复评价应失败
test_step "18. 居民重复评价应失败"
DUP_REVIEW=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"rating": 1, "comment": "重复评价尝试改分"}')

if echo "$DUP_REVIEW" | grep -q "重复评价" > /dev/null 2>&1; then
  test_pass "重复评价被拒绝"
else
  echo "响应: $DUP_REVIEW"
  test_fail "重复评价未被拒绝"
fi

echo ""

# 19. 志愿者评价订单
test_step "19. 志愿者评价订单"
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

# 20. 订单状态过滤：待确认/已完成/已评价
test_step "20. 订单状态过滤（待确认/已完成/已评价）"
PENDING_LIST=$(curl -s "$BASE_URL/orders?status=pending_confirm" -H "Authorization: Bearer $VOLUNTEER_TOKEN")
PENDING_COUNT=$(echo "$PENDING_LIST" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['orders']))")
REVIEWED_LIST=$(curl -s "$BASE_URL/orders?status=reviewed" -H "Authorization: Bearer $VOLUNTEER_TOKEN")
REVIEWED_HAS=$(echo "$REVIEWED_LIST" | python3 -c "import sys,json; print(any(o['id'] == $ORDER_ID for o in json.load(sys.stdin)['orders']))")
COMPLETED_LIST=$(curl -s "$BASE_URL/orders?status=completed" -H "Authorization: Bearer $VOLUNTEER_TOKEN")
COMPLETED_HAS=$(echo "$COMPLETED_LIST" | python3 -c "import sys,json; print(any(o['id'] == $ORDER_ID for o in json.load(sys.stdin)['orders']))")

if [ "$REVIEWED_HAS" = "True" ] && [ "$COMPLETED_HAS" = "False" ]; then
  test_pass "双方评价后订单进入已评价列表，不再出现在待评价列表 (待确认列表 $PENDING_COUNT 条)"
else
  test_fail "订单状态过滤异常: reviewed=$REVIEWED_HAS, completed(待评价)=$COMPLETED_HAS"
fi

echo ""

# 21. 获取志愿者信息（验证积分与时长）
test_step "21. 获取志愿者信息（验证积分与时长只结算一次）"
PROFILE_RES=$(curl -s "$BASE_URL/user/profile" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$PROFILE_RES" | grep -q "points" > /dev/null 2>&1; then
  POINTS=$(echo "$PROFILE_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")
  HOURS=$(echo "$PROFILE_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['service_hours'])")
  EXPECTED_POINTS=$((INITIAL_POINTS + 20))
  if [ "$POINTS" = "$EXPECTED_POINTS" ]; then
    test_pass "积分正确: $POINTS (原 $INITIAL_POINTS + 服务2小时 20积分), 总服务时长: $HOURS 小时"
  else
    test_fail "积分异常: $POINTS (预期 $EXPECTED_POINTS)"
  fi
else
  test_fail "获取用户信息失败"
fi

echo ""

# 22. 测试兑换礼品
test_step "22. 志愿者兑换礼品 (保温杯 100 积分)"
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

# 23. 测试获取兑换记录
test_step "23. 获取兑换记录"
EXCHANGES_RES=$(curl -s "$BASE_URL/my/exchanges" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$EXCHANGES_RES" | grep -q "exchanges" > /dev/null 2>&1; then
  EX_COUNT=$(echo "$EXCHANGES_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['exchanges']))")
  EX_GIFT=$(echo "$EXCHANGES_RES" | python3 -c "import sys,json; e=json.load(sys.stdin)['exchanges'][0]; print(f'{e[\"name\"]} ({e[\"points\"]}积分)')")
  test_pass "获取到 $EX_COUNT 条兑换记录，最新: $EX_GIFT"
else
  echo "响应: $EXCHANGES_RES"
  test_fail "获取兑换记录失败"
fi

echo ""

# 24. 测试发送消息
test_step "24. 发送消息"
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

# 25. 测试获取消息列表
test_step "25. 获取消息列表"
MSGS_RES=$(curl -s "$BASE_URL/messages?other_user_id=$VOLUNTEER_ID" \
  -H "Authorization: Bearer $RESIDENT_TOKEN")

if echo "$MSGS_RES" | grep -q "messages" > /dev/null 2>&1; then
  MSG_COUNT=$(echo "$MSGS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['messages']))")
  test_pass "获取到 $MSG_COUNT 条消息"
else
  echo "响应: $MSGS_RES"
  test_fail "获取消息列表失败"
fi

echo ""

# 26. 测试积分排名
test_step "26. 获取志愿者排名"
RANKING_RES=$(curl -s "$BASE_URL/users/ranking")
if echo "$RANKING_RES" | grep -q "ranking" > /dev/null 2>&1; then
  RANK_COUNT=$(echo "$RANKING_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['ranking']))")
  TOP_NAME=$(echo "$RANKING_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['ranking'][0]['name'])")
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
echo "   ✅ 发布需求"
echo "   ✅ 需求列表查询"
echo "   ✅ 接单"
echo "   ✅ 志愿者登记服务结果（时长+结果），订单进入待确认"
echo "   ✅ 重复登记被拒绝，已登记结果不被覆盖"
echo "   ✅ 未完成订单评价被拒绝"
echo "   ✅ 志愿者不能替居民确认"
echo "   ✅ 居民确认完成，积分与时长结算（2小时=20积分）"
echo "   ✅ 重复确认被拒绝，积分只结算一次"
echo "   ✅ 需求状态同步收口"
echo "   ✅ 非参与人评价被拒绝"
echo "   ✅ 双方各评价一次，重复评价被拒绝"
echo "   ✅ 订单状态过滤（待确认/已完成/已评价）"
echo "   ✅ 积分兑换礼品（保温杯100积分）"
echo "   ✅ 兑换记录查询"
echo "   ✅ 消息发送/接收"
echo "   ✅ 积分排名"
echo ""
echo "🎮 现在可以打开浏览器访问 http://localhost:8233 体验完整功能"
echo ""
