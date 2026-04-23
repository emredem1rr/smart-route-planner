CREATE DATABASE IF NOT EXISTS smart_route_planner;
USE smart_route_planner;

CREATE TABLE IF NOT EXISTS users (
  id                      INT AUTO_INCREMENT PRIMARY KEY,
  name                    VARCHAR(100) NOT NULL,
  email                   VARCHAR(150) NOT NULL UNIQUE,
  phone                   VARCHAR(20)  NOT NULL UNIQUE,
  password_hash           VARCHAR(255) NOT NULL,
  is_verified             TINYINT(1)   NOT NULL DEFAULT 0,
  verification_code       VARCHAR(10)  DEFAULT NULL,
  verification_expires    DATETIME     DEFAULT NULL,
  created_at              TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  updated_at              TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
                          ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id     INT         NOT NULL,
  token       VARCHAR(10) NOT NULL,
  expires_at  DATETIME    NOT NULL,
  UNIQUE KEY  uq_user (user_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_tasks (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT           NOT NULL,
  name            VARCHAR(200)  NOT NULL,
  address         VARCHAR(500)  DEFAULT '',
  latitude        DOUBLE        NOT NULL,
  longitude       DOUBLE        NOT NULL,
  duration        INT           NOT NULL DEFAULT 30,
  priority        INT           NOT NULL DEFAULT 3,
  earliest_start  INT           NOT NULL DEFAULT 0,
  latest_finish   INT           NOT NULL DEFAULT 480,
  task_date       DATE          NOT NULL DEFAULT (CURDATE()),
  status          ENUM('pending','done','cancelled')
                               NOT NULL DEFAULT 'pending',
  is_recurring    TINYINT(1)   NOT NULL DEFAULT 0,
  recurrence_type VARCHAR(20)  DEFAULT NULL,
  recurrence_days VARCHAR(50)  DEFAULT NULL,
  created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);