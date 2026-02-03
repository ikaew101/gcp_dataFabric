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

# ==========================================
# 5. CLOUD FUNCTIONS (UPDATED FIX)
# ==========================================

# 5.1 เปิดใช้งาน API ที่จำเป็น (เพิ่ม Artifact Registry)
resource "google_project_service" "cf_service" {
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "build_service" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry_api" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# 5.2 สร้าง Service Account ขึ้นมาเอง (ไม่ต้องง้อ Default)
resource "google_service_account" "function_sa" {
  account_id   = "sensor-function-sa"
  display_name = "Service Account for Sensor Data Function"
}

# 5.3 ให้สิทธิ์ Service Account นี้เขียนลง BigQuery ได้
resource "google_project_iam_member" "function_bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# 5.4 ให้สิทธิ์ Service Account นี้อ่าน Artifact Registry ได้ (แก้ Error ตัวบน)
resource "google_project_iam_member" "function_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# 5.5 เตรียมไฟล์ Zip
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/function_code"
  output_path = "${path.module}/function_source.zip"
}

# 5.6 อัปโหลดไฟล์ Zip
resource "google_storage_bucket_object" "function_archive" {
  name   = "source-code-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_zip.output_path
}

# 5.7 สร้าง Cloud Function (โดยบังคับให้ใช้ Service Account ที่เราสร้าง)
resource "google_cloudfunctions_function" "data_ingest_function" {
  name        = "sensor-data-ingester"
  description = "Ingest sensor data from Pub/Sub to BigQuery"
  runtime     = "python310"

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.function_archive.name
  
  # Trigger
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.ingest_topic.name
  }

  entry_point = "process_sensor_data"
  
  environment_variables = {
    TABLE_ID = "${var.project_id}.${google_bigquery_dataset.analytics_ds.dataset_id}.test_table"
  }

  # --- จุดสำคัญ: สั่งให้ใช้ Service Account ของเรา ---
  service_account_email = google_service_account.function_sa.email

  depends_on = [
    google_project_service.cf_service,
    google_project_service.build_service,
    google_project_service.artifact_registry_api,
    google_project_iam_member.function_artifact_reader
  ]
}