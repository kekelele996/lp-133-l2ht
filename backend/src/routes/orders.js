const { Router } = require('express');
const pool = require('../../db');
const messages = require('../constants/messages');
const { authenticateToken } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');

const router = Router();

const POINTS_PER_HOUR = 10;
const MIN_SERVICE_HOURS = 0.5;
const MAX_SERVICE_HOURS = 24;

router.get('/', authenticateToken, asyncHandler(async (req, res) => {
  const { status } = req.query;
  let sql = `SELECT o.*, n.title, n.type, n.address,
    u1.name as user_name, u2.name as volunteer_name,
    (SELECT COUNT(*) FROM reviews r WHERE r.order_id = o.id) as review_count,
    EXISTS(SELECT 1 FROM reviews r WHERE r.order_id = o.id AND r.reviewer_id = ?) as my_reviewed
    FROM orders o
    LEFT JOIN needs n ON o.need_id = n.id
    LEFT JOIN users u1 ON o.user_id = u1.id
    LEFT JOIN users u2 ON o.volunteer_id = u2.id
    WHERE (o.user_id = ? OR o.volunteer_id = ?)`;
  const params = [req.user.id, req.user.id, req.user.id];

  if (status === 'completed') {
    // 已完成待评价：已确认完成但当前用户尚未评价
    sql += ` AND o.status = 'completed'
      AND NOT EXISTS(SELECT 1 FROM reviews r WHERE r.order_id = o.id AND r.reviewer_id = ?)`;
    params.push(req.user.id);
  } else if (status === 'reviewed') {
    // 已评价：已确认完成且当前用户已评价
    sql += ` AND o.status = 'completed'
      AND EXISTS(SELECT 1 FROM reviews r WHERE r.order_id = o.id AND r.reviewer_id = ?)`;
    params.push(req.user.id);
  } else if (status) {
    sql += ' AND o.status = ?';
    params.push(status);
  }

  sql += ' ORDER BY o.created_at DESC';

  const [rows] = await pool.query(sql, params);
  res.json({ orders: rows });
}));

// 志愿者登记服务时长和结果，订单进入待居民确认
router.put('/:id/finish', authenticateToken, asyncHandler(async (req, res) => {
  const { service_hours, result } = req.body;
  const orderId = req.params.id;

  const hours = Number(service_hours);
  if (!Number.isFinite(hours) || hours < MIN_SERVICE_HOURS || hours > MAX_SERVICE_HOURS) {
    return res.status(400).json({ message: messages.orders.invalidHours });
  }

  const resultText = typeof result === 'string' ? result.trim() : '';
  if (!resultText) {
    return res.status(400).json({ message: messages.orders.missingResult });
  }

  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (orders[0].volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.onlyVolunteer });
  }

  // 条件更新：仅进行中订单可登记，重复提交或并发请求由 affectedRows 兜底
  const [update] = await pool.query(
    "UPDATE orders SET status = 'pending_confirm', service_hours = ?, result = ?, end_time = NOW() WHERE id = ? AND status = 'in_progress'",
    [hours, resultText, orderId],
  );

  if (update.affectedRows === 0) {
    return res.status(409).json({ message: messages.orders.stateConflict });
  }

  res.json({ message: messages.orders.finished });
}));

// 居民核对后确认完成，订单和需求收口，积分与时长只结算一次
router.put('/:id/confirm', authenticateToken, asyncHandler(async (req, res) => {
  const orderId = req.params.id;
  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  const order = orders[0];

  if (order.user_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.onlyResident });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    // 条件更新是唯一的结算入口：并发或重复确认时，后到的请求 affectedRows 为 0，
    // 不能改掉已确定的结果，积分与时长也只结算一次
    const [update] = await connection.query(
      "UPDATE orders SET status = 'completed' WHERE id = ? AND status = 'pending_confirm'",
      [orderId],
    );

    if (update.affectedRows === 0) {
      await connection.rollback();
      return res.status(409).json({ message: messages.orders.stateConflict });
    }

    await connection.query(
      "UPDATE needs SET status = 'completed' WHERE id = ?",
      [order.need_id],
    );

    const hours = Number(order.service_hours);
    const points = Math.round(hours * POINTS_PER_HOUR);
    await connection.query(
      'UPDATE users SET service_hours = service_hours + ?, points = points + ? WHERE id = ?',
      [hours, points, order.volunteer_id],
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

// 订单完成后，双方各评价一次
router.post('/:id/review', authenticateToken, asyncHandler(async (req, res) => {
  const { rating, comment } = req.body;
  const orderId = req.params.id;

  const score = Number(rating);
  if (!Number.isInteger(score) || score < 1 || score > 5) {
    return res.status(400).json({ message: messages.orders.invalidRating });
  }

  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  const order = orders[0];

  if (order.user_id !== req.user.id && order.volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.notParticipant });
  }

  if (order.status !== 'completed') {
    return res.status(400).json({ message: messages.orders.notCompleted });
  }

  const targetId = order.user_id === req.user.id
    ? order.volunteer_id
    : order.user_id;

  try {
    await pool.query(
      'INSERT INTO reviews (order_id, reviewer_id, target_id, rating, comment) VALUES (?, ?, ?, ?, ?)',
      [orderId, req.user.id, targetId, score, comment],
    );
  } catch (err) {
    // (order_id, reviewer_id) 唯一索引兜底：重复评价（含并发重复提交）明确失败
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ message: messages.orders.duplicateReview });
    }
    throw err;
  }

  res.json({ message: messages.orders.reviewed });
}));

module.exports = router;
