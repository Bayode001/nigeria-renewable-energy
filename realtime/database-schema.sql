-- Nigeria Renewable Energy Historical Database Schema
-- PostgreSQL 13+

-- Enable PostGIS for geographic queries
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- States reference table
CREATE TABLE states (
    id SERIAL PRIMARY KEY,
    state_code VARCHAR(10) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    region VARCHAR(50),
    capital VARCHAR(100),
    population INTEGER,
    area_km2 DECIMAL(10,2),
    geometry GEOMETRY(MultiPolygon, 4326),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Energy sources reference
CREATE TABLE energy_sources (
    id SERIAL PRIMARY KEY,
    source_code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    unit VARCHAR(20),
    min_value DECIMAL(10,4),
    max_value DECIMAL(10,4),
    is_active BOOLEAN DEFAULT TRUE
);

INSERT INTO energy_sources (source_code, name, description, unit) VALUES
    ('SOLAR', 'Solar Energy', 'Solar radiation potential', 'kWh/m²/day'),
    ('WIND', 'Wind Energy', 'Wind speed at 10m height', 'm/s'),
    ('HYDRO', 'Hydro Energy', 'Hydropower potential', 'index'),
    ('COMPOSITE', 'Composite Score', 'Overall renewable energy potential', 'index');

-- Historical energy data (time-series)
CREATE TABLE energy_measurements (
    time TIMESTAMPTZ NOT NULL,
    state_id INTEGER REFERENCES states(id),
    source_id INTEGER REFERENCES energy_sources(id),
    value DECIMAL(10,4) NOT NULL,
    normalized_value DECIMAL(10,4),
    confidence DECIMAL(5,4) DEFAULT 1.0,
    data_source VARCHAR(100),
    raw_value JSONB,
    metadata JSONB,
    PRIMARY KEY (time, state_id, source_id)
);

-- Convert to TimescaleDB hypertable for time-series optimization
SELECT create_hypertable('energy_measurements', 'time');

-- Create indexes for performance
CREATE INDEX idx_energy_measurements_state ON energy_measurements(state_id);
CREATE INDEX idx_energy_measurements_source ON energy_measurements(source_id);
CREATE INDEX idx_energy_measurements_time_state ON energy_measurements(time, state_id);
CREATE INDEX idx_energy_measurements_gin_raw ON energy_measurements USING GIN (raw_value);
CREATE INDEX idx_energy_measurements_gin_metadata ON energy_measurements USING GIN (metadata);

-- Daily aggregates for faster queries
CREATE TABLE energy_daily_aggregates (
    date DATE NOT NULL,
    state_id INTEGER REFERENCES states(id),
    source_id INTEGER REFERENCES energy_sources(id),
    avg_value DECIMAL(10,4),
    min_value DECIMAL(10,4),
    max_value DECIMAL(10,4),
    stddev_value DECIMAL(10,4),
    sample_count INTEGER,
    PRIMARY KEY (date, state_id, source_id)
);

-- Monthly aggregates
CREATE TABLE energy_monthly_aggregates (
    year_month CHAR(7) NOT NULL, -- YYYY-MM format
    state_id INTEGER REFERENCES states(id),
    source_id INTEGER REFERENCES energy_sources(id),
    avg_value DECIMAL(10,4),
    trend DECIMAL(10,4), -- Month-over-month change
    percentile_25 DECIMAL(10,4),
    percentile_50 DECIMAL(10,4),
    percentile_75 DECIMAL(10,4),
    PRIMARY KEY (year_month, state_id, source_id)
);

-- Regional summaries
CREATE TABLE regional_summaries (
    date DATE NOT NULL,
    region VARCHAR(50) NOT NULL,
    source_id INTEGER REFERENCES energy_sources(id),
    avg_value DECIMAL(10,4),
    state_count INTEGER,
    best_state_id INTEGER REFERENCES states(id),
    worst_state_id INTEGER REFERENCES states(id),
    PRIMARY KEY (date, region, source_id)
);

-- Data quality monitoring
CREATE TABLE data_quality_log (
    id SERIAL PRIMARY KEY,
    check_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    check_type VARCHAR(50),
    source_id INTEGER REFERENCES energy_sources(id),
    status VARCHAR(20), -- 'success', 'warning', 'error'
    message TEXT,
    records_processed INTEGER,
    processing_time_ms INTEGER,
    details JSONB
);

-- Alert configurations
CREATE TABLE alert_configurations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    source_id INTEGER REFERENCES energy_sources(id),
    condition_type VARCHAR(50), -- 'threshold', 'anomaly', 'missing'
    condition_params JSONB NOT NULL,
    severity VARCHAR(20), -- 'info', 'warning', 'critical'
    notification_channels JSONB, -- ['email', 'slack', 'webhook']
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Alert history
CREATE TABLE alert_history (
    id SERIAL PRIMARY KEY,
    alert_config_id INTEGER REFERENCES alert_configurations(id),
    triggered_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMPTZ,
    state_id INTEGER REFERENCES states(id),
    source_id INTEGER REFERENCES energy_sources(id),
    current_value DECIMAL(10,4),
    threshold_value DECIMAL(10,4),
    message TEXT,
    status VARCHAR(20) DEFAULT 'active', -- 'active', 'resolved', 'acknowledged'
    acknowledged_by VARCHAR(100),
    acknowledged_at TIMESTAMPTZ,
    resolution_notes TEXT
);

-- API access logs
CREATE TABLE api_access_log (
    id SERIAL PRIMARY KEY,
    access_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    endpoint VARCHAR(200),
    method VARCHAR(10),
    client_ip INET,
    user_agent TEXT,
    response_time_ms INTEGER,
    status_code INTEGER,
    parameters JSONB,
    response_size INTEGER
);

-- Views for common queries

-- Current state of energy measurements
CREATE VIEW current_energy_state AS
SELECT 
    s.name as state_name,
    s.region,
    es.name as energy_source,
    em.value,
    em.normalized_value,
    em.time as last_updated,
    em.data_source
FROM energy_measurements em
JOIN states s ON em.state_id = s.id
JOIN energy_sources es ON em.source_id = es.id
WHERE em.time = (
    SELECT MAX(time) 
    FROM energy_measurements 
    WHERE state_id = em.state_id 
    AND source_id = em.source_id
);

-- Regional averages view
CREATE VIEW regional_energy_summary AS
SELECT 
    date,
    region,
    es.name as energy_source,
    rs.avg_value,
    s_best.name as best_state,
    s_worst.name as worst_state
FROM regional_summaries rs
JOIN energy_sources es ON rs.source_id = es.id
LEFT JOIN states s_best ON rs.best_state_id = s_best.id
LEFT JOIN states s_worst ON rs.worst_state_id = s_worst.id
ORDER BY date DESC, region, energy_source;

-- Functions

-- Function to update aggregates
CREATE OR REPLACE FUNCTION update_daily_aggregates()
RETURNS TRIGGER AS $$
BEGIN
    -- Update daily aggregates
    INSERT INTO energy_daily_aggregates 
    SELECT 
        DATE(NEW.time),
        NEW.state_id,
        NEW.source_id,
        AVG(value),
        MIN(value),
        MAX(value),
        STDDEV(value),
        COUNT(*)
    FROM energy_measurements
    WHERE DATE(time) = DATE(NEW.time)
        AND state_id = NEW.state_id
        AND source_id = NEW.source_id
    ON CONFLICT (date, state_id, source_id) DO UPDATE SET
        avg_value = EXCLUDED.avg_value,
        min_value = EXCLUDED.min_value,
        max_value = EXCLUDED.max_value,
        stddev_value = EXCLUDED.stddev_value,
        sample_count = EXCLUDED.sample_count;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for daily aggregates
CREATE TRIGGER trigger_update_daily_aggregates
AFTER INSERT ON energy_measurements
FOR EACH ROW
EXECUTE FUNCTION update_daily_aggregates();

-- Function to check for alerts
CREATE OR REPLACE FUNCTION check_energy_alerts()
RETURNS TRIGGER AS $$
DECLARE
    alert_config RECORD;
    threshold_val DECIMAL;
BEGIN
    -- Check all active alert configurations for this source
    FOR alert_config IN 
        SELECT * FROM alert_configurations 
        WHERE source_id = NEW.source_id 
        AND is_active = TRUE
    LOOP
        IF alert_config.condition_type = 'threshold' THEN
            threshold_val := (alert_config.condition_params->>'threshold')::DECIMAL;
            
            IF NEW.value > threshold_val THEN
                INSERT INTO alert_history (
                    alert_config_id, 
                    state_id, 
                    source_id,
                    current_value,
                    threshold_value,
                    message
                ) VALUES (
                    alert_config.id,
                    NEW.state_id,
                    NEW.source_id,
                    NEW.value,
                    threshold_val,
                    'Value ' || NEW.value || ' exceeds threshold ' || threshold_val
                );
            END IF;
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for alerts
CREATE TRIGGER trigger_check_alerts
AFTER INSERT ON energy_measurements
FOR EACH ROW
EXECUTE FUNCTION check_energy_alerts();

-- Create roles and permissions
CREATE ROLE energy_reader;
CREATE ROLE energy_writer;
CREATE ROLE energy_admin;

-- Grant permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO energy_reader;
GRANT SELECT, INSERT, UPDATE ON energy_measurements, data_quality_log TO energy_writer;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO energy_admin;

-- Create API user
CREATE USER api_user WITH PASSWORD 'secure_password_here';
GRANT energy_reader TO api_user;

-- Create ingestion user for n8n workflow
CREATE USER n8n_ingestor WITH PASSWORD 'another_secure_password';
GRANT energy_writer TO n8n_ingestor;

-- Create indexes for spatial queries
CREATE INDEX idx_states_geometry ON states USING GIST (geometry);

-- Vacuum and analyze settings
ALTER TABLE energy_measurements SET (
    autovacuum_vacuum_scale_factor = 0.1,
    autovacuum_analyze_scale_factor = 0.05
);

COMMENT ON DATABASE nigeria_energy IS 'Nigeria Renewable Energy Historical Database';
COMMENT ON TABLE energy_measurements IS 'Time-series measurements of renewable energy potential across Nigerian states';