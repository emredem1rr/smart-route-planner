const express  = require('express');
const router   = express.Router();
const { validateOptimizeRequest } = require('../middleware/validateRequest');
const { optimize }                = require('../controllers/optimizeController');

router.post('/optimize', validateOptimizeRequest, optimize);

module.exports = router;