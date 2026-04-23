const pool                       = require('../config/db');
const { callOptimizationEngine } = require('../services/pythonService');

async function optimize(req, res) {
  const { start_location, tasks, config = {}, user_id = 1 } = req.body;

  let optimizationResult;
  try {
    optimizationResult = await callOptimizationEngine({
      start_location,
      tasks,
      config,
    });
  } catch (err) {
    return res.status(err.status || 500).json({
      success: false,
      error:   err.message,
    });
  }

  const result = optimizationResult.result;
  let routeId;
  const conn = await pool.getConnection();

  try {
    await conn.beginTransaction();

    const [routeRow] = await conn.execute(
      `INSERT INTO routes
         (user_id, start_latitude, start_longitude, ordered_task_ids,
          total_travel_time, total_distance, total_fitness_score,
          algorithm_used, heuristic_used, random_seed, execution_time_ms)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        user_id,
        start_location.latitude,
        start_location.longitude,
        JSON.stringify(result.ordered_task_ids),
        result.total_travel_time,
        result.total_distance,
        result.fitness_score,
        result.algorithm_used,
        result.heuristic_used,
        result.random_seed,
        result.execution_time_ms,
      ]
    );

    routeId = routeRow.insertId;

    for (const log of optimizationResult.comparison_logs || []) {
      await conn.execute(
        `INSERT INTO optimization_logs
           (route_id, algorithm, heuristic, fitness_score,
            total_distance, execution_time_ms, random_seed)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          routeId,
          log.algorithm,
          log.heuristic,
          log.fitness_score,
          log.total_distance,
          log.execution_time_ms,
          log.random_seed,
        ]
      );
    }

    await conn.commit();
  } catch (dbErr) {
    await conn.rollback();
    console.error('[DB] Failed to save route:', dbErr.message);
  } finally {
    conn.release();
  }

  return res.status(200).json({
    success:          true,
    route_id:         routeId,
    result,
    comparison_logs:  optimizationResult.comparison_logs,
  });
}

module.exports = { optimize };