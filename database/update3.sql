USE smart_route_planner;

CREATE TABLE IF NOT EXISTS route_history (
  id                INT AUTO_INCREMENT PRIMARY KEY,
  user_id           INT           NOT NULL,
  task_date         DATE          NOT NULL,
  total_distance    DOUBLE        DEFAULT 0,
  total_travel_time DOUBLE        DEFAULT 0,
  algorithm_used    VARCHAR(50)   DEFAULT '',
  fitness_score     DOUBLE        DEFAULT 0,
  execution_time_ms DOUBLE        DEFAULT 0,
  task_names        TEXT,
  task_count        INT           DEFAULT 0,
  created_at        TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
