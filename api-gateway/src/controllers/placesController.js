const pool = require('../config/db');

// ── Favori ekle ────────────────────────────────────────────
async function addFavorite(req, res) {
  const user_id = req.user.user_id;
  const { place_id, name, address, latitude, longitude, rating, types } = req.body;
  try {
    await pool.execute(
      `INSERT INTO favorite_places (user_id, place_id, name, address, latitude, longitude, rating, types)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE name = VALUES(name)`,
      [user_id, place_id, name, address || '', latitude, longitude, rating || 0,
       Array.isArray(types) ? types.join(',') : (types || '')]
    );
    return res.status(201).json({ success: true });
  } catch (err) {
    console.error('[Places] Add favorite error:', err.message);
    return res.status(500).json({ success: false, error: 'Favori eklenemedi.' });
  }
}

// ── Favori kaldır ──────────────────────────────────────────
async function removeFavorite(req, res) {
  const user_id  = req.user.user_id;
  const { place_id } = req.params;
  try {
    await pool.execute(
      'DELETE FROM favorite_places WHERE user_id = ? AND place_id = ?',
      [user_id, place_id]
    );
    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Favori kaldırılamadı.' });
  }
}

// ── Favorileri getir ───────────────────────────────────────
async function getFavorites(req, res) {
  const user_id = req.user.user_id;
  try {
    const [rows] = await pool.execute(
      'SELECT * FROM favorite_places WHERE user_id = ? ORDER BY created_at DESC',
      [user_id]
    );
    return res.status(200).json({ success: true, places: rows });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Favoriler alınamadı.' });
  }
}

// ── Favori mi kontrol et ───────────────────────────────────
async function checkFavorite(req, res) {
  const user_id  = req.user.user_id;
  const { place_id } = req.params;
  try {
    const [rows] = await pool.execute(
      'SELECT id FROM favorite_places WHERE user_id = ? AND place_id = ?',
      [user_id, place_id]
    );
    return res.status(200).json({ success: true, is_favorite: rows.length > 0 });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Kontrol edilemedi.' });
  }
}

// ── Yorum ekle / güncelle ──────────────────────────────────
async function addReview(req, res) {
  const user_id = req.user.user_id;
  const { place_id, place_name, rating, comment } = req.body;

  if (!place_id || !rating || !comment?.trim()) {
    return res.status(400).json({ success: false, error: 'Eksik alan.' });
  }
  if (rating < 1 || rating > 5) {
    return res.status(400).json({ success: false, error: 'Puan 1-5 arasında olmalı.' });
  }

  try {
    // Kullanıcının bu mekan için yorumu var mı?
    const [existing] = await pool.execute(
      'SELECT id FROM place_reviews WHERE user_id = ? AND place_id = ?',
      [user_id, place_id]
    );

    if (existing.length > 0) {
      // Güncelle
      await pool.execute(
        'UPDATE place_reviews SET rating = ?, comment = ? WHERE user_id = ? AND place_id = ?',
        [rating, comment.trim(), user_id, place_id]
      );
    } else {
      // Yeni ekle
      await pool.execute(
        'INSERT INTO place_reviews (user_id, place_id, place_name, rating, comment) VALUES (?, ?, ?, ?, ?)',
        [user_id, place_id, place_name || '', rating, comment.trim()]
      );
    }
    return res.status(201).json({ success: true });
  } catch (err) {
    console.error('[Places] Add review error:', err.message);
    return res.status(500).json({ success: false, error: 'Yorum kaydedilemedi.' });
  }
}

// ── Mekan yorumlarını getir ────────────────────────────────
async function getReviews(req, res) {
  const { place_id } = req.params;
  try {
    const [rows] = await pool.execute(
      `SELECT pr.id, pr.rating, pr.comment, pr.created_at,
              u.name AS user_name
       FROM place_reviews pr
       JOIN users u ON u.id = pr.user_id
       WHERE pr.place_id = ?
       ORDER BY pr.created_at DESC`,
      [place_id]
    );
    // Ortalama puan
    const avg = rows.length > 0
      ? rows.reduce((s, r) => s + r.rating, 0) / rows.length
      : 0;

    return res.status(200).json({
      success: true,
      reviews: rows,
      avg_rating: Math.round(avg * 10) / 10,
      count: rows.length,
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Yorumlar alınamadı.' });
  }
}

// ── Yorum sil ─────────────────────────────────────────────
async function deleteReview(req, res) {
  const user_id   = req.user.user_id;
  const { id }    = req.params;
  try {
    await pool.execute(
      'DELETE FROM place_reviews WHERE id = ? AND user_id = ?',
      [id, user_id]
    );
    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Yorum silinemedi.' });
  }
}

module.exports = {
  addFavorite, removeFavorite, getFavorites, checkFavorite,
  addReview, getReviews, deleteReview,
};