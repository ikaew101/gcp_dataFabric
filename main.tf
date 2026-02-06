provider "google" {
  project = var.project_id
  region  = "asia-southeast1"
}

provider "google-beta" {
  project = var.project_id
  region  = "asia-southeast1"
}

variable "project_id" {
  default = "cis-dev-ai-smart-mirror" 
}

# ==========================================
# 1. PREPARE SERVICES (เปิด API)
# ==========================================
resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "apigateway.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicecontrol.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

# ==========================================
# 2. CLOUD SQL (DATABASE)
# ==========================================
# 2.1 สร้าง Instance (Server)
resource "google_sql_database_instance" "main_instance" {
  name             = "sensor-db-instance-${random_id.db_name_suffix.hex}"
  database_version = "POSTGRES_14"
  region           = "asia-southeast1"
  deletion_protection = false # เพื่อให้ Terraform Destroy ได้ง่าย

  settings {
    tier = "db-f1-micro" # เล็กสุดเพื่อประหยัดเงิน
    activation_policy = "ALWAYS" # ค่าเริ่มต้นให้เปิดไว้ก่อน

    ip_configuration {
        ipv4_enabled = true # เปิด Public IP (เพื่อให้ Looker ต่อได้ง่าย)
        authorized_networks {
          name  = "allow-all" # (Dev Only) เพื่อให้ต่อจากคอมเราได้
          value = "0.0.0.0/0"
        }
    }
  }
  lifecycle {
    ignore_changes = [
      settings[0].activation_policy
    ]
  }

  depends_on = [google_project_service.services]
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

# 2.2 สร้าง Database ข้างใน
resource "google_sql_database" "database" {
  name     = "sensor_data"
  instance = google_sql_database_instance.main_instance.name
}

# 2.3 สร้าง User สำหรับ Login
resource "google_sql_user" "users" {
  name     = "sensor_user"
  instance = google_sql_database_instance.main_instance.name
  password = "admin123!" # ควรเปลี่ยนใน Production
}

# ==========================================
# 3. CLOUD RUN (BACKEND APP)
# ==========================================
# 3.1 Artifact Registry (ที่เก็บ Image)
resource "google_artifact_registry_repository" "app_repo" {
  location      = "asia-southeast1"
  repository_id = "my-apps"
  format        = "DOCKER"
  depends_on    = [google_project_service.services]
}

# 3.2 Build Image (ส่ง Code ขึ้น Cloud Build)
resource "null_resource" "build_backend" {
  triggers = {
    always_run = "${timestamp()}"
  }
  provisioner "local-exec" {
    # สั่ง Build จาก folder 'backend_source'
    command = "gcloud builds submit --tag asia-southeast1-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_repo.repository_id}/dashboard-backend:latest backend_source"
  }
  depends_on = [google_artifact_registry_repository.app_repo]
}

# 3.3 Deploy Cloud Run
resource "google_cloud_run_service" "backend_service" {
  name     = "dashboard-backend"
  location = "asia-southeast1"

  template {
    metadata {
      annotations = {
        # สำคัญ: เชื่อมต่อ Cloud SQL
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.main_instance.connection_name
        "run.googleapis.com/client-name"        = "terraform"
      }
    }
    spec {
      containers {
        image = "asia-southeast1-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_repo.repository_id}/dashboard-backend:latest"
        
        # ส่งค่า Config Database ให้ Python
        env {
          name  = "DB_USER"
          value = google_sql_user.users.name
        }
        env {
          name  = "DB_PASS"
          value = google_sql_user.users.password
        }
        env {
          name  = "DB_NAME"
          value = google_sql_database.database.name
        }
        env {
          name  = "INSTANCE_CONNECTION_NAME"
          value = google_sql_database_instance.main_instance.connection_name
        }
      }
    }
  }
  depends_on = [null_resource.build_backend, google_sql_database_instance.main_instance]
}


# ==========================================
# 4. API GATEWAY
# ==========================================
# 4.1 สร้าง API Config (โดยอ่านจากไฟล์ yaml และแทนค่า URL)
resource "google_api_gateway_api" "api_gw" {
  provider = google-beta
  project  = var.project_id
  api_id   = "sensor-api"
  depends_on = [google_project_service.services]
}

resource "google_api_gateway_api_config" "api_cfg" {
  provider      = google-beta
  api           = google_api_gateway_api.api_gw.api_id
  api_config_id_prefix = "sensor-config-"

  openapi_documents {
    document {
      path = "spec.yaml"
      contents = base64encode(templatefile("api_config.yaml.tpl", {
        cloud_run_url = google_cloud_run_service.backend_service.status[0].url
      }))
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

# 4.2 สร้าง Gateway (ตัวรับ Request จริงๆ)
resource "google_api_gateway_gateway" "gw" {
  provider   = google-beta
  api_config = google_api_gateway_api_config.api_cfg.id
  gateway_id = "sensor-gateway"
  region     = "asia-northeast1"

  timeouts {
    create = "45m"
    update = "45m"
    delete = "20m"
  }
}

# Output: บอก URL ของ Gateway
output "gateway_url" {
  value = google_api_gateway_gateway.gw.default_hostname
}
# ==========================================
# 5. SCHEDULER (AUTO START/STOP CLOUD SQL)
# ==========================================

# 5.1 เปิดใช้งาน Cloud Scheduler API
resource "google_project_service" "scheduler_api" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

# 5.2 สร้าง Service Account ให้ Scheduler มีสิทธิ์สั่ง SQL ได้
resource "google_service_account" "scheduler_sa" {
  account_id   = "sql-scheduler-sa"
  display_name = "Service Account for SQL Scheduler"
}

resource "google_project_iam_member" "scheduler_sql_editor" {
  project = var.project_id
  role    = "roles/cloudsql.editor"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# 5.3 ตั้งเวลา "เปิด" เครื่อง (Start)
resource "google_cloud_scheduler_job" "start_sql_job" {
  name             = "start-sql-instance"
  description      = "Start Cloud SQL instance at 8:30 AM BKK time"
  schedule         = "30 8 * * 1-5" 
  time_zone        = "Asia/Bangkok"
  attempt_deadline = "320s"

  http_target {
    http_method = "PATCH"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${google_sql_database_instance.main_instance.name}"
    
    # ส่งคำสั่ง activationPolicy = ALWAYS (เปิด)
    body = base64encode("{\"settings\": {\"activationPolicy\": \"ALWAYS\"}}")

    oauth_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }
  depends_on = [google_project_service.scheduler_api]
}

# 5.4 ตั้งเวลา "ปิด" เครื่อง (Stop)
resource "google_cloud_scheduler_job" "stop_sql_job" {
  name             = "stop-sql-instance"
  description      = "Stop Cloud SQL instance at 5:30 PM BKK time"
  schedule         = "30 17 * * 1-5"
  time_zone        = "Asia/Bangkok"
  attempt_deadline = "320s"

  http_target {
    http_method = "PATCH"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${google_sql_database_instance.main_instance.name}"

    # ส่งคำสั่ง activationPolicy = NEVER (ปิด)
    body = base64encode("{\"settings\": {\"activationPolicy\": \"NEVER\"}}")

    oauth_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }
  depends_on = [google_project_service.scheduler_api]
}