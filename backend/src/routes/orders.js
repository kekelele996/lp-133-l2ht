const { Router } = require('express');
const pool = require('../../db');
const messages = require('../constants/messages');
const { authenticateToken } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');

const router = Router();

const MIN_SERVICE_HOURS = 0.5;
const MAX_SERVICE_HOURS = 24;
const POINTS_PER_HOUR = 10;

router.get('/', authenticateToken, asyncHandler(async (req, res) => {
  const { status } = req.query;
  let sql = `SELECT o.*, n.title, n.type, n.address,
    u1.name as user_name, u2.name as volunteer_name,
    (SELECT COUNT(*) FROM reviews r WHERE r.order_id = o.id AND r.reviewer_id = ?) as my_reviewed,
    (SELECT COUNT(*) FROM reviews r2 WHERE r2.order_id = o.id) as review_count
    FROM orders o
    LEFT JOIN needs n ON o.need_id = n.id
    LEFT JOIN users u1 ON o.user_id = u1.id
    LEFT JOIN users u2 ON o.volunteer_id = u2.id
    WHERE o.user_id = ? OR o.volunteer_id = ?`;
  const params = [req.user.id, req.user.id, req.user.id];

  if (status) {
    sql += ' AND o.status = ?';
    params.push(status);
  }

  sql += ' ORDER BY o.created_at DESC';

  const [rows] = await pool.query(sql, params);
  res.json({ orders: rows });
}));

// 志愿者登记服务结果：订单进入待居民确认状态，此时不结算积分
router.put('/:id/report', authenticateToken, asyncHandler(async (req, res) => {
  const { service_hours, service_result } = req.body;
  const orderId = req.params.id;

  const hours = Number(service_hours);
  if (!Number.isFinite(hours) || hours < MIN_SERVICE_HOURS || hours > MAX_SERVICE_HOURS) {
    return res.status(400).json({ message: messages.orders.invalidHours });
  }

  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  const order = orders[0];

  if (order.volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.reportForbidden });
  }

  if (order.status !== 'in_progress') {
    return res.status(409).json({ message: messages.orders.notInProgress });
  }

  const resultText = typeof service_result === 'string'
    ? service_result.trim().slice(0, 500)
    : null;

  // 条件更新保证并发/重复提交时只有第一个请求生效
  const [update] = await pool.query(
    "UPDATE orders SET status = 'pending_confirm', service_hours = ?, service_result = ?, end_time = NOW() WHERE id = ? AND status = 'in_progress'",
    [hours, resultText, orderId],
  );

  if (update.affectedRows === 0) {
    return res.status(409).json({ message: messages.orders.reportConflict });
  }

  res.json({ message: messages.orders.reported });
}));

// 居民确认完成：订单与需求收口，积分与时长在此结算且只结算一次
router.put('/:id/confirm', authenticateToken, asyncHandler(async (req, res) => {
  const orderId = req.params.id;
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    // 行锁使并发确认串行化，后到的请求看到已确定的结果
    const [orders] = await connection.query('SELECT * FROM orders WHERE id = ? FOR UPDATE', [orderId]);

    if (orders.length === 0) {
      await connection.rollback();
      return res.status(404).json({ message: messages.orders.notFound });
    }

    const order = orders[0];

    if (order.user_id !== req.user.id) {
      await connection.rollback();
      return res.status(403).json({ message: messages.orders.confirmForbidden });
    }

    if (order.status !== 'pending_confirm') {
      await connection.rollback();
      const message = order.status === 'completed'
        ? messages.orders.confirmConflict
        : messages.orders.notPendingConfirm;
      return res.status(409).json({ message });
    }

    // settled 标志 + 条件更新双重保证积分只结算一次
    const [update] = await connection.query(
      "UPDATE orders SET status = 'completed', settled = 1 WHERE id = ? AND status = 'pending_confirm' AND settled = 0",
      [orderId],
    );

    if (update.affectedRows === 0) {
      await connection.rollback();
      return res.status(409).json({ message: messages.orders.confirmConflict });
    }

    await connection.query(
      "UPDATE needs SET status = 'completed' WHERE id = ?",
      [order.need_id],
    );

    const points = Math.round(Number(order.service_hours) * POINTS_PER_HOUR);
    await connection.query(
      'UPDATE users SET service_hours = service_hours + ?, points = points + ? WHERE id = ?',
      [order.service_hours, points, order.volunteer_id],
    );

    await connection.commit();
    res.json({ message: messages.orders.confirmed });
  } catch (err) {
    await connection.rollback();
    throw err;
  } finally {
    connection.release();
  }
}));

// 双方各评价一次：仅订单参与者、仅订单完成后、每人限一次
router.post('/:id/review', authenticateToken, asyncHandler(async (req, res) => {
  const { rating, comment } = req.body;
  const orderId = req.params.id;
  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  const order = orders[0];
  const isParticipant = order.user_id === req.user.id || order.volunteer_id === req.user.id;

  if (!isParticipant) {
    return res.status(403).json({ message: messages.orders.reviewForbidden });
  }

  if (order.status !== 'completed') {
    return res.status(400).json({ message: messages.orders.reviewNotCompleted });
  }

  const score = Number(rating);
  if (!Number.isInteger(score) || score < 1 || score > 5) {
    return res.status(400).json({ message: messages.orders.invalidRating });
  }

  const targetId = order.user_id === req.user.id
    ? order.volunteer_id
    : order.user_id;

  const commentText = typeof comment === 'string' ? comment.trim() : null;

  const [existing] = await pool.query(
    'SELECT id FROM reviews WHERE order_id = ? AND reviewer_id = ?',
    [orderId, req.user.id],
  );

  if (existing.length > 0) {
    return res.status(409).json({ message: messages.orders.alreadyReviewed });
  }

  try {
    await pool.query(
      'INSERT INTO reviews (order_id, reviewer_id, target_id, rating, comment) VALUES (?, ?, ?, ?, ?)',
      [orderId, req.user.id, targetId, score, commentText],
    );
  } catch (err) {
    // 唯一索引兜底：并发重复评价时后到的请求明确失败
    if (err && err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ message: messages.orders.alreadyReviewed });
    }
    throw err;
  }

  res.json({ message: messages.orders.reviewed });
}));

module.exports = router;
