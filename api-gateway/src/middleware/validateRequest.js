const { body, validationResult } = require('express-validator');

const validateOptimizeRequest = [
  body('start_location.latitude')
    .isFloat({ min: -90, max: 90 })
    .withMessage('start_location.latitude must be a float between -90 and 90'),
  body('start_location.longitude')
    .isFloat({ min: -180, max: 180 })
    .withMessage('start_location.longitude must be a float between -180 and 180'),
  body('tasks')
    .isArray({ min: 1 })
    .withMessage('tasks must be a non-empty array'),
  body('tasks.*.id')
    .isInt({ min: 1 })
    .withMessage('Each task must have a positive integer id'),
  body('tasks.*.name')
    .isString().trim().notEmpty()
    .withMessage('Each task must have a non-empty name'),
  body('tasks.*.latitude')
    .isFloat({ min: -90, max: 90 })
    .withMessage('Task latitude must be between -90 and 90'),
  body('tasks.*.longitude')
    .isFloat({ min: -180, max: 180 })
    .withMessage('Task longitude must be between -180 and 180'),
  body('tasks.*.duration')
    .isInt({ min: 1 })
    .withMessage('Task duration must be a positive integer (minutes)'),
  body('tasks.*.priority')
    .isInt({ min: 1, max: 5 })
    .withMessage('Task priority must be between 1 and 5'),
  body('tasks.*.earliest_start')
    .isInt({ min: 0 })
    .withMessage('earliest_start must be a non-negative integer'),
  body('tasks.*.latest_finish')
    .isInt({ min: 1 })
    .withMessage('latest_finish must be a positive integer'),
  body('config.heuristic')
    .optional()
    .isIn(['euclidean', 'manhattan'])
    .withMessage('heuristic must be "euclidean" or "manhattan"'),
  body('config.seed')
    .optional().isInt(),
  body('config.population_size')
    .optional().isInt({ min: 10 }),
  body('config.generations')
    .optional().isInt({ min: 10 }),
  body('config.crossover_rate')
    .optional().isFloat({ min: 0.1, max: 1.0 }),
  body('config.mutation_rate')
    .optional().isFloat({ min: 0.01, max: 1.0 }),
  body('config.elitism_size')
    .optional().isInt({ min: 1 }),

  (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        errors:  errors.array().map(e => ({ field: e.path, message: e.msg })),
      });
    }
    next();
  },
];

module.exports = { validateOptimizeRequest };