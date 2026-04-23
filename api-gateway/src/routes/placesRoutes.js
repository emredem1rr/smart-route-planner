const express = require('express');
const router  = express.Router();
const {
  addFavorite, removeFavorite, getFavorites, checkFavorite,
  addReview, getReviews, deleteReview,
} = require('../controllers/placesController');
const { authenticateToken } = require('../middleware/authMiddleware');

// Favoriler
router.get   ('/places/favorites',         authenticateToken, getFavorites);
router.post  ('/places/favorites',         authenticateToken, addFavorite);
router.delete('/places/favorites/:place_id', authenticateToken, removeFavorite);
router.get   ('/places/favorites/:place_id/check', authenticateToken, checkFavorite);

// Yorumlar
router.get   ('/places/:place_id/reviews', getReviews);          // herkese açık
router.post  ('/places/reviews',           authenticateToken, addReview);
router.delete('/places/reviews/:id',       authenticateToken, deleteReview);

module.exports = router;