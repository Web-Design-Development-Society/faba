-- TODO: Create the db schema
-- Activities table for FABA (Faculty Associations Board Activities)
CREATE TABLE IF NOT EXISTS activities (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  date TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
