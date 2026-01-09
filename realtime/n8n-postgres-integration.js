// n8n Node for PostgreSQL Integration
// Add this as a new Function node after "SAFE Update Logic Node"

const { Client } = require('pg');

async function run() {
    console.log('=== POSTGRESQL INTEGRATION STARTED ===');
    
    const processedData = $input.first().json;
    
    if (!processedData || processedData.error) {
        console.log('❌ Skipping database update - invalid data');
        return $input.all();
    }
    
    // Database configuration
    const dbConfig = {
        host: process.env.DB_HOST || 'localhost',
        port: process.env.DB_PORT || 5432,
        database: process.env.DB_NAME || 'nigeria_energy',
        user: process.env.DB_USER || 'n8n_ingestor',
        password: process.env.DB_PASSWORD || 'your_password',
        ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
    };
    
    const client = new Client(dbConfig);
    
    try {
        await client.connect();
        console.log('✅ Connected to PostgreSQL database');
        
        const timestamp = new Date().toISOString();
        
        // Start transaction
        await client.query('BEGIN');
        
        // Process each feature (state)
        for (const feature of processedData.features) {
            const props = feature.properties;
            const stateName = props.ADM1_EN;
            
            // Get state ID
            const stateRes = await client.query(
                'SELECT id FROM states WHERE name = $1',
                [stateName]
            );
            
            let stateId;
            if (stateRes.rows.length === 0) {
                // Insert new state if not exists
                const insertRes = await client.query(
                    `INSERT INTO states (name, state_code, region) 
                     VALUES ($1, $2, $3) 
                     RETURNING id`,
                    [stateName, stateName.toUpperCase().replace(/ /g, '_'), props.region || 'Unknown']
                );
                stateId = insertRes.rows[0].id;
                console.log(`✅ Inserted new state: ${stateName}`);
            } else {
                stateId = stateRes.rows[0].id;
            }
            
            // Insert energy measurements
            const measurements = [
                { source: 'SOLAR', value: props.solar_norm, raw: props.solar_norm },
                { source: 'WIND', value: props.wind_norm, raw: props.wind_norm },
                { source: 'HYDRO', value: props.hydro_norm, raw: props.hydro_norm },
                { source: 'COMPOSITE', value: props.composite_norm, raw: props.composite_norm }
            ];
            
            for (const measurement of measurements) {
                await client.query(
                    `INSERT INTO energy_measurements 
                     (time, state_id, source_id, value, normalized_value, data_source, metadata) 
                     VALUES (
                         $1, 
                         $2, 
                         (SELECT id FROM energy_sources WHERE source_code = $3), 
                         $4, 
                         $5, 
                         $6,
                         $7
                     )
                     ON CONFLICT (time, state_id, source_id) DO UPDATE SET
                         value = EXCLUDED.value,
                         normalized_value = EXCLUDED.normalized_value,
                         data_source = EXCLUDED.data_source,
                         metadata = EXCLUDED.metadata`,
                    [
                        timestamp,
                        stateId,
                        measurement.source,
                        measurement.value,
                        measurement.value,
                        'n8n_real_time',
                        JSON.stringify({
                            classification: props[`${measurement.source.toLowerCase()}_class`],
                            confidence: props.confidence_level,
                            recommended: props.recommended_energy,
                            last_updated: props.last_updated
                        })
                    ]
                );
            }
        }
        
        // Update data quality log
        await client.query(
            `INSERT INTO data_quality_log 
             (check_time, check_type, status, records_processed, details) 
             VALUES ($1, $2, $3, $4, $5)`,
            [
                timestamp,
                'real_time_update',
                'success',
                processedData.features.length,
                JSON.stringify({
                    national_scores: processedData.national_scores,
                    data_sources: processedData.data_sources,
                    features_updated: processedData.features_updated
                })
            ]
        );
        
        // Commit transaction
        await client.query('COMMIT');
        console.log(`✅ Successfully inserted ${processedData.features.length} state records`);
        
        // Check for alerts
        const alertRes = await client.query(
            `SELECT COUNT(*) as alert_count FROM alert_history 
             WHERE triggered_at > NOW() - INTERVAL '1 hour' 
             AND status = 'active'`
        );
        
        if (alertRes.rows[0].alert_count > 0) {
            console.log(`⚠️ ${alertRes.rows[0].alert_count} active alerts in the last hour`);
        }
        
    } catch (error) {
        await client.query('ROLLBACK');
        console.error('❌ Database error:', error.message);
        
        // Log the error but don't fail the workflow
        return $input.all();
        
    } finally {
        await client.end();
        console.log('✅ Database connection closed');
    }
    
    return $input.all();
}

// Execute the function
return await run();