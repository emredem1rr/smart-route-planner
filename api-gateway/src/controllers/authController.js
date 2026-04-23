const bcrypt     = require('bcrypt');
const jwt        = require('jsonwebtoken');
const nodemailer = require('nodemailer');
const pool       = require('../config/db');

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: { user: process.env.EMAIL_USER, pass: process.env.EMAIL_PASS },
});

async function register(req, res) {
  const { name, email, phone, password } = req.body;
  try {
    const [byEmail] = await pool.execute('SELECT id FROM users WHERE email = ?', [email]);
    if (byEmail.length > 0) return res.status(409).json({ success: false, error: 'Bu e-posta zaten kayıtlı.' });

    const [byPhone] = await pool.execute('SELECT id FROM users WHERE phone = ?', [phone]);
    if (byPhone.length > 0) return res.status(409).json({ success: false, error: 'Bu telefon numarası zaten kayıtlı.' });

    const passwordHash = await bcrypt.hash(password, 10);
    const verifyCode   = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt    = new Date(Date.now() + 10 * 60 * 1000);

    await pool.execute(
      `INSERT INTO users (name, email, phone, password_hash, verification_code, verification_expires, is_verified)
       VALUES (?, ?, ?, ?, ?, ?, 0)`,
      [name, email, phone, passwordHash, verifyCode, expiresAt]
    );

    await transporter.sendMail({
      from: process.env.EMAIL_USER, to: email,
      subject: 'Smart Route — E-posta Doğrulama',
      html: `<h2>Doğrulama Kodunuz</h2><p>Merhaba ${name},</p><p>Doğrulama kodunuz: <strong style="font-size:24px">${verifyCode}</strong></p><p>Bu kod 10 dakika geçerlidir.</p>`,
    });

    return res.status(201).json({ success: true, requires_verification: true });
  } catch (err) {
    console.error('[Auth] Register error:', err.message);
    return res.status(500).json({ success: false, error: 'Kayıt işlemi başarısız.' });
  }
}

async function verifyEmail(req, res) {
  const { email, code } = req.body;
  try {
    const [users] = await pool.execute(
      'SELECT id, name, email, verification_code, verification_expires FROM users WHERE email = ?', [email]
    );
    if (users.length === 0) return res.status(404).json({ success: false, error: 'Kullanıcı bulunamadı.' });

    const user = users[0];
    if (user.verification_code !== code) return res.status(400).json({ success: false, error: 'Doğrulama kodu hatalı.' });
    if (new Date() > new Date(user.verification_expires)) return res.status(400).json({ success: false, error: 'Doğrulama kodu süresi doldu.' });

    await pool.execute(
      'UPDATE users SET is_verified = 1, verification_code = NULL, verification_expires = NULL WHERE id = ?',
      [user.id]
    );

    const token = jwt.sign({ user_id: user.id, email: user.email }, process.env.JWT_SECRET, { expiresIn: '30d' });
    return res.status(200).json({ success: true, token, user: { id: user.id, name: user.name, email: user.email } });
  } catch (err) {
    console.error('[Auth] Verify email error:', err.message);
    return res.status(500).json({ success: false, error: 'Doğrulama başarısız.' });
  }
}

async function login(req, res) {
  const { identifier, password } = req.body;
  try {
    const [users] = await pool.execute(
      'SELECT id, name, email, phone, password_hash, is_verified FROM users WHERE email = ? OR phone = ?',
      [identifier, identifier]
    );
    if (users.length === 0) return res.status(401).json({ success: false, error: 'Kullanıcı bulunamadı.' });

    const user = users[0];
    if (!user.is_verified) return res.status(403).json({ success: false, error: 'E-posta doğrulanmamış.' });

    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) return res.status(401).json({ success: false, error: 'Şifre hatalı.' });

    const token = jwt.sign({ user_id: user.id, email: user.email }, process.env.JWT_SECRET, { expiresIn: '30d' });
    return res.status(200).json({ success: true, token, user: { id: user.id, name: user.name, email: user.email } });
  } catch (err) {
    console.error('[Auth] Login error:', err.message);
    return res.status(500).json({ success: false, error: 'Giriş başarısız.' });
  }
}

async function forgotPassword(req, res) {
  const { email } = req.body;
  try {
    const [users] = await pool.execute('SELECT id, name FROM users WHERE email = ?', [email]);
    if (users.length === 0) return res.status(404).json({ success: false, error: 'Bu e-posta kayıtlı değil.' });

    const user      = users[0];
    const resetCode = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    await pool.execute(
      'INSERT INTO password_reset_tokens (user_id, token, expires_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE token = ?, expires_at = ?',
      [user.id, resetCode, expiresAt, resetCode, expiresAt]
    );

    await transporter.sendMail({
      from: process.env.EMAIL_USER, to: email,
      subject: 'Smart Route — Şifre Sıfırlama',
      html: `<h2>Şifre Sıfırlama</h2><p>Merhaba ${user.name},</p><p>Şifre sıfırlama kodunuz: <strong style="font-size:24px">${resetCode}</strong></p><p>Bu kod 10 dakika geçerlidir.</p>`,
    });

    return res.status(200).json({ success: true });
  } catch (err) {
    console.error('[Auth] Forgot password error:', err.message);
    return res.status(500).json({ success: false, error: 'Kod gönderilemedi.' });
  }
}

async function resetPassword(req, res) {
  const { email, reset_code, new_password } = req.body;
  try {
    const [users] = await pool.execute('SELECT id FROM users WHERE email = ?', [email]);
    if (users.length === 0) return res.status(404).json({ success: false, error: 'Kullanıcı bulunamadı.' });

    const userId  = users[0].id;
    const [tokens] = await pool.execute(
      'SELECT token, expires_at FROM password_reset_tokens WHERE user_id = ? AND token = ?',
      [userId, reset_code]
    );

    if (tokens.length === 0) return res.status(400).json({ success: false, error: 'Geçersiz kod.' });
    if (new Date() > new Date(tokens[0].expires_at)) return res.status(400).json({ success: false, error: 'Kodun süresi doldu.' });

    const newHash = await bcrypt.hash(new_password, 10);
    await pool.execute('UPDATE users SET password_hash = ? WHERE id = ?', [newHash, userId]);
    await pool.execute('DELETE FROM password_reset_tokens WHERE user_id = ?', [userId]);

    return res.status(200).json({ success: true });
  } catch (err) {
    console.error('[Auth] Reset password error:', err.message);
    return res.status(500).json({ success: false, error: 'Şifre sıfırlanamadı.' });
  }
}

async function getProfile(req, res) {
  const user_id = req.user.user_id;
  try {
    const [users] = await pool.execute(
      'SELECT id, name, email, phone, created_at FROM users WHERE id = ?', [user_id]
    );
    if (users.length === 0) return res.status(404).json({ success: false, error: 'Kullanıcı bulunamadı.' });
    return res.status(200).json({ success: true, user: users[0] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Profil alınamadı.' });
  }
}

async function updateProfile(req, res) {
  const user_id         = req.user.user_id;
  const { name, phone } = req.body;
  try {
    if (phone) {
      const [byPhone] = await pool.execute('SELECT id FROM users WHERE phone = ? AND id != ?', [phone, user_id]);
      if (byPhone.length > 0) return res.status(409).json({ success: false, error: 'Bu telefon numarası başka bir hesapta kullanılıyor.' });
    }
    await pool.execute('UPDATE users SET name = ?, phone = ? WHERE id = ?', [name, phone || null, user_id]);
    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Profil güncellenemedi.' });
  }
}

async function changePassword(req, res) {
  const user_id                            = req.user.user_id;
  const { current_password, new_password } = req.body;
  try {
    const [users] = await pool.execute('SELECT password_hash FROM users WHERE id = ?', [user_id]);
    if (users.length === 0) return res.status(404).json({ success: false, error: 'Kullanıcı bulunamadı.' });

    const isMatch = await bcrypt.compare(current_password, users[0].password_hash);
    if (!isMatch) return res.status(401).json({ success: false, error: 'Mevcut şifre hatalı.' });

    const newHash = await bcrypt.hash(new_password, 10);
    await pool.execute('UPDATE users SET password_hash = ? WHERE id = ?', [newHash, user_id]);
    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Şifre değiştirilemedi.' });
  }
}

async function deleteAccount(req, res) {
  const user_id      = req.user.user_id;
  const { password } = req.body;
  try {
    const [users] = await pool.execute('SELECT password_hash FROM users WHERE id = ?', [user_id]);
    if (users.length === 0) return res.status(404).json({ success: false, error: 'Kullanıcı bulunamadı.' });

    const isMatch = await bcrypt.compare(password, users[0].password_hash);
    if (!isMatch) return res.status(401).json({ success: false, error: 'Şifre hatalı.' });

    await pool.execute('DELETE FROM users WHERE id = ?', [user_id]);
    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Hesap silinemedi.' });
  }
}

async function getUserTasks(req, res) {
  const user_id                              = req.user.user_id;
  const { date, status, date_from, date_to } = req.query;

  try {
    let query  = `SELECT * FROM user_tasks WHERE user_id = ?`;
    let params = [user_id];

    if (date)      { query += ` AND task_date = ?`;    params.push(date); }
    if (date_from) { query += ` AND task_date >= ?`;   params.push(date_from); }
    if (date_to)   { query += ` AND task_date <= ?`;   params.push(date_to); }
    if (status)    { query += ` AND status = ?`;       params.push(status); }

    query += ` ORDER BY task_date DESC, id DESC`;

    const [tasks] = await pool.execute(query, params);
    return res.status(200).json({ success: true, tasks });
  } catch (err) {
    console.error('[Auth] Get tasks error:', err.message);
    return res.status(500).json({ success: false, error: 'Görevler alınamadı.' });
  }
}

async function getTaskDates(req, res) {
  const user_id         = req.user.user_id;
  const { month, year } = req.query;

  try {
    const [dates] = await pool.execute(
      `SELECT
         DATE_FORMAT(task_date, '%Y-%m-%d') AS task_date,
         SUM(CASE WHEN status = 'pending'   THEN 1 ELSE 0 END) AS pending_count,
         SUM(CASE WHEN status = 'done'      THEN 1 ELSE 0 END) AS done_count,
         SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count
       FROM user_tasks
       WHERE user_id = ?
         AND MONTH(task_date) = ?
         AND YEAR(task_date)  = ?
       GROUP BY task_date
       ORDER BY task_date`,
      [user_id, month, year]
    );
    return res.status(200).json({ success: true, dates });
  } catch (err) {
    console.error('[Auth] Get task dates error:', err.message);
    return res.status(500).json({ success: false, error: 'Takvim verileri alınamadı.' });
  }
}

async function saveTask(req, res) {
  const user_id = req.user.user_id;
  const {
    name, address, latitude, longitude,
    duration, priority, earliest_start, latest_finish,
    task_date, is_recurring, recurrence_type, recurrence_days,
  } = req.body;

  try {
    const [result] = await pool.execute(
      `INSERT INTO user_tasks
         (user_id, name, address, latitude, longitude,
          duration, priority, earliest_start, latest_finish,
          task_date, is_recurring, recurrence_type, recurrence_days)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        user_id, name, address, latitude, longitude,
        duration, priority, earliest_start, latest_finish,
        task_date || new Date().toISOString().split('T')[0],
        is_recurring ? 1 : 0, recurrence_type || null, recurrence_days || null,
      ]
    );
    return res.status(201).json({ success: true, task_id: result.insertId });
  } catch (err) {
    console.error('[Auth] Save task error:', err.message);
    return res.status(500).json({ success: false, error: 'Görev kaydedilemedi.' });
  }
}

async function updateTask(req, res) {
  const user_id = req.user.user_id;
  const { id }  = req.params;
  const {
    name, address, latitude, longitude,
    duration, priority, earliest_start, latest_finish,
    task_date, is_recurring, recurrence_type, recurrence_days,
  } = req.body;

  try {
    await pool.execute(
      `UPDATE user_tasks
       SET name = ?, address = ?, latitude = ?, longitude = ?,
           duration = ?, priority = ?, earliest_start = ?,
           latest_finish = ?, task_date = ?,
           is_recurring = ?, recurrence_type = ?, recurrence_days = ?
       WHERE id = ? AND user_id = ?`,
      [
        name, address, latitude, longitude,
        duration, priority, earliest_start, latest_finish,
        task_date,
        is_recurring ? 1 : 0, recurrence_type || null, recurrence_days || null,
        id, user_id,
      ]
    );
    return res.status(200).json({ success: true });
  } catch (err) {
    console.error('[Auth] Update task error:', err.message);
    return res.status(500).json({ success: false, error: 'Görev güncellenemedi.' });
  }
}

async function updateTaskStatus(req, res) {
  const user_id    = req.user.user_id;
  const { id }     = req.params;
  const { status } = req.body;

  const valid = ['pending', 'done', 'cancelled'];
  if (!valid.includes(status)) {
    return res.status(400).json({ success: false, error: 'Geçersiz durum.' });
  }

  try {
    await pool.execute(
      'UPDATE user_tasks SET status = ? WHERE id = ? AND user_id = ?',
      [status, id, user_id]
    );
    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Durum güncellenemedi.' });
  }
}

// ── Delete task — tekrarlayan görevler için delete_all desteği ─
async function deleteTask(req, res) {
  const user_id        = req.user.user_id;
  const { id }         = req.params;
  const { delete_all } = req.query;

  try {
    if (delete_all === 'true') {
      // Önce görevin adını al
      const [rows] = await pool.execute(
        'SELECT name FROM user_tasks WHERE id = ? AND user_id = ?',
        [id, user_id]
      );
      if (rows.length === 0) {
        return res.status(404).json({ success: false, error: 'Görev bulunamadı.' });
      }
      // Aynı isme sahip tüm tekrarlayan görevleri sil
      await pool.execute(
        'DELETE FROM user_tasks WHERE user_id = ? AND name = ? AND is_recurring = 1',
        [user_id, rows[0].name]
      );
    } else {
      // Sadece bu görevi sil
      await pool.execute(
        'DELETE FROM user_tasks WHERE id = ? AND user_id = ?',
        [id, user_id]
      );
    }
    return res.status(200).json({ success: true });
  } catch (err) {
    console.error('[Auth] Delete task error:', err.message);
    return res.status(500).json({ success: false, error: 'Görev silinemedi.' });
  }
}

async function resendVerification(req, res) {
  const { email } = req.body;
  try {
    const [users] = await pool.execute('SELECT id, name FROM users WHERE email = ?', [email]);
    if (users.length === 0) return res.status(404).json({ success: false, error: 'Kullanıcı bulunamadı.' });

    const verifyCode = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt  = new Date(Date.now() + 10 * 60 * 1000);

    await pool.execute(
      'UPDATE users SET verification_code = ?, verification_expires = ? WHERE id = ?',
      [verifyCode, expiresAt, users[0].id]
    );

    await transporter.sendMail({
      from: process.env.EMAIL_USER, to: email,
      subject: 'Smart Route — Doğrulama Kodu',
      html: `<p>Yeni doğrulama kodunuz: <strong>${verifyCode}</strong></p>`,
    });

    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Kod gönderilemedi.' });
  }
}

module.exports = {
  register, verifyEmail, resendVerification,
  login, forgotPassword, resetPassword,
  getProfile, updateProfile, changePassword, deleteAccount,
  getUserTasks, getTaskDates,
  saveTask, updateTask, updateTaskStatus, deleteTask,
  getRouteHistory, saveRouteHistory,
};

// ── Rota geçmişini getir ───────────────────────────────────
async function getRouteHistory(req, res) {
  const user_id = req.user.user_id;
  try {
    const [routes] = await pool.execute(
      `SELECT id, task_date, total_distance, total_travel_time,
              algorithm_used, fitness_score, execution_time_ms,
              task_names, task_count, created_at
       FROM route_history
       WHERE user_id = ?
       ORDER BY created_at DESC
       LIMIT 20`,
      [user_id]
    );
    return res.status(200).json({ success: true, routes });
  } catch (err) {
    // Tablo yoksa boş döndür
    return res.status(200).json({ success: true, routes: [] });
  }
}

// ── Rota geçmişine kaydet ──────────────────────────────────
async function saveRouteHistory(req, res) {
  const user_id = req.user.user_id;
  const {
    task_date, total_distance, total_travel_time,
    algorithm_used, fitness_score, execution_time_ms,
    task_names, task_count,
  } = req.body;
  try {
    await pool.execute(
      `INSERT INTO route_history
         (user_id, task_date, total_distance, total_travel_time,
          algorithm_used, fitness_score, execution_time_ms,
          task_names, task_count)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [user_id, task_date, total_distance, total_travel_time,
       algorithm_used, fitness_score, execution_time_ms,
       task_names, task_count]
    );
    return res.status(201).json({ success: true });
  } catch (err) {
    console.error('[RouteHistory] Save error:', err.message);
    return res.status(500).json({ success: false, error: 'Geçmiş kaydedilemedi.' });
  }
}