const express = require('express');
const router  = express.Router();
const {
  register,
  verifyEmail,
  login,
  forgotPassword,
  resetPassword,
  getProfile,
  updateProfile,
  changePassword,
  deleteAccount,
  getUserTasks,
  getTaskDates,
  saveTask,
  updateTask,
  updateTaskStatus,
  deleteTask,
  resendVerification,
  getRouteHistory,
  saveRouteHistory,
} = require('../controllers/authController');
const { authenticateToken } = require('../middleware/authMiddleware');

// Auth
router.post('/auth/register',             register);
router.post('/auth/verify-email',         verifyEmail);
router.post('/auth/resend-verification',  resendVerification);
router.post('/auth/login',                login);
router.post('/auth/forgot-password',      forgotPassword);
router.post('/auth/reset-password',       resetPassword);

// Profile
router.get   ('/profile',                 authenticateToken, getProfile);
router.put   ('/profile',                 authenticateToken, updateProfile);
router.post  ('/profile/change-password', authenticateToken, changePassword);
router.delete('/profile',                 authenticateToken, deleteAccount);

// Tasks
router.get   ('/tasks',                   authenticateToken, getUserTasks);
router.get   ('/tasks/dates',             authenticateToken, getTaskDates);
router.post  ('/tasks',                   authenticateToken, saveTask);
router.put   ('/tasks/:id',               authenticateToken, updateTask);
router.patch ('/tasks/:id/status',        authenticateToken, updateTaskStatus);
router.delete('/tasks/:id',               authenticateToken, deleteTask);

// Route history
router.get ('/routes/history',            authenticateToken, getRouteHistory);
router.post('/routes/history',            authenticateToken, saveRouteHistory);

module.exports = router;