# filename: api_config.yaml.tpl
swagger: '2.0'
info:
  title: Sensor API
  description: API for ingesting sensor data to Cloud SQL
  version: 1.0.0
schemes:
  - https
produces:
  - application/json
paths:
  /ingest:
    post:
      summary: Ingest Sensor Data
      operationId: ingestData
      x-google-backend:
        address: ${cloud_run_url}/ingest
        protocol: h2
      responses:
        '200':
          description: OK
        '400':
          description: Bad Request