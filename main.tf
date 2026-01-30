provider "google" {
  project = "cis-dev-ai-smart-mirror"
  region  = "asia-southeast1"
}

# ==========================================
# 1. INGEST (ส่วนนำเข้าข้อมูล)
# ==========================================

# 1.1 Cloud Pub/Sub
resource "google_pubsub_topic" "ingest_topic" {
  name = "ingest_cis_datafabric"
}

# 1.2 Cloud Functions (Source Code Bucket)
resource "google_storage_bucket" "function_bucket" {
  name                        = "fn_source_cis_datafabric"
  location                    = "ASIA-SOUTHEAST1"
  uniform_bucket_level_access = true
}

# 1.3 API Gateway (Enable Service)
resource "google_project_service" "api_gateway_service" {
  service = "apigateway.googleapis.com"
  disable_on_destroy = false
}

# ==========================================
# 2. PROCESSING (ส่วนประมวลผล)
# ==========================================

# 2.1 Cloud Storage (Raw Data / Staging)
resource "google_storage_bucket" "raw_data_bucket" {
  name          = "cis_datafabric_raw"
  location      = "ASIA-SOUTHEAST1"
  force_destroy = true
}

# 2.2 Dataflow (ETL) --- [COMMENTED OUT: COST SAVING] ---
# resource "google_project_service" "dataflow_service" {
#   service = "dataflow.googleapis.com"
#   disable_on_destroy = false
# }
# (ในอนาคต: ถ้าจะรัน Dataflow Job จริงๆ ต้องเขียน resource "google_dataflow_job" เพิ่มตรงนี้)

# ==========================================
# 3. STORAGE & ANALYTIC (ส่วนจัดเก็บและวิเคราะห์)
# ==========================================

# 3.1 Cloud SQL --- [COMMENTED OUT: COST SAVING] ---
# resource "google_sql_database_instance" "main_instance" {
#   name             = "main-db-instance"
#   database_version = "POSTGRES_14"
#   region           = "asia-southeast1"
#   deletion_protection = false 
#
#   settings {
#     tier = "db-f1-micro"
#   }
# }
#
# resource "google_sql_database" "database" {
#   name     = "business-data"
#   instance = google_sql_database_instance.main_instance.name
# }

# 3.2 BigQuery
resource "google_bigquery_dataset" "analytics_ds" {
  dataset_id    = "cis_datafabric_dataset"
  friendly_name = "Analytics Data Warehouse"
  location      = "ASIA-SOUTHEAST1"
}

# 3.3 Cloud Run (Backend Dashboard)
resource "google_cloud_run_service" "backend_service" {
  name     = "dashboard-backend"
  location = "asia-southeast1"

  template {
    spec {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello"
      }
    }
  }
}

# 3.4 Vertex AI (Gemini) - Enable API
resource "google_project_service" "vertex_ai_service" {
  service = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

# ==========================================
# 4. Variables
# ==========================================
variable "project_id" {
  description = "The ID of the Google Cloud project"
  default     = "cis-dev-ai-smart-mirror"
}