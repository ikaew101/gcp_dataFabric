import base64
import json
import os
from google.cloud import bigquery

# ตั้งค่า Client ไว้ข้างนอกเพื่อให้ Reuse Connection (Best Practice)
bq_client = bigquery.Client()
# อ่านชื่อ Table จาก Environment Variable ที่เราจะตั้งใน Terraform
TABLE_ID = os.environ.get('TABLE_ID') 

def process_sensor_data(event, context):
    """Triggered from a message on a Cloud Pub/Sub topic."""
    try:
        # 1. แกะซองจดหมาย (Decode Pub/Sub Message)
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        payload = json.loads(pubsub_message)
        
        print(f"Received payload: {payload}")

        # 2. ปรับข้อมูลให้อยู่ในรูปแบบ List เสมอ (เพื่อรองรับทั้งแบบส่งเดี่ยวและส่งเป็นชุด)
        rows_to_insert = []
        if isinstance(payload, list):
            rows_to_insert = payload  # ถ้ามาเป็น Array อยู่แล้วก็ใช้เลย
        else:
            rows_to_insert = [payload] # ถ้ามาตัวเดียว ให้จับใส่ List

        # 3. ยิงเข้า BigQuery
        errors = bq_client.insert_rows_json(TABLE_ID, rows_to_insert)

        if errors == []:
            print(f"Successfully inserted {len(rows_to_insert)} rows.")
        else:
            print(f"Encountered errors: {errors}")
            # ยก Error เพื่อให้ Pub/Sub รู้ว่าส่งไม่สำเร็จ (และจะลองส่งใหม่)
            raise RuntimeError(f"BigQuery Insert Errors: {errors}")

    except Exception as e:
        print(f"Error processing message: {e}")
        raise e