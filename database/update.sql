USE smart_route_planner;

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  user_id    INT UNSIGNED  NOT NULL,
  token      VARCHAR(255)  NOT NULL UNIQUE,
  expires_at TIMESTAMP     NOT NULL,
  used       TINYINT(1)    NOT NULL DEFAULT 0,
  created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_reset_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_tasks (
  id             INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  user_id        INT UNSIGNED     NOT NULL,
  name           VARCHAR(150)     NOT NULL,
  address        VARCHAR(255)     NOT NULL DEFAULT '',
  latitude       DECIMAL(10, 7)   NOT NULL,
  longitude      DECIMAL(10, 7)   NOT NULL,
  duration       INT UNSIGNED     NOT NULL,
  priority       TINYINT UNSIGNED NOT NULL DEFAULT 3,
  earliest_start INT UNSIGNED     NOT NULL DEFAULT 0,
  latest_finish  INT UNSIGNED     NOT NULL,
  created_at     TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_user_tasks FOREIGN KEY (user_id)
    REFERENCES users(id) ON DELETE CASCADE
);