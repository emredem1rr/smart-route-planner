USE smart_route_planner;

-- Telefon numarası ekle
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20) DEFAULT NULL;