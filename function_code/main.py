import base64
import json
import os
from datetime import datetime
from google.cloud import bigquery

# Reuse Connection เพื่อประสิทธิภาพ
bq_client = bigquery.Client()
TABLE_ID = os.environ.get('TABLE_ID')

def process_sensor_data(event, context):
    try:
        # 1. แกะซองจดหมาย (Decode Message)
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        raw_payload = json.loads(pubsub_message)
        
        print(f"Original Payload: {raw_payload}")

        # 2. Normalize: ทำให้เป็น List เสมอ (เผื่อส่งมาเดี่ยวหรือมาเป็นชุด)
        items = raw_payload if isinstance(raw_payload, list) else [raw_payload]
        
        rows_to_insert = []
        current_time = datetime.utcnow().isoformat()

        # 3. Loop จัดเตรียมข้อมูลลงถังกลาง
        for item in items:
            # Logic: พยายามหาว่าใครส่งมา (จาก key 'source' หรือ 'type' หรือ 'device_type')
            # ถ้าหาไม่เจอ ให้ระบุเป็น 'unknown'
            source_type = item.get('source', item.get('type', 'unknown'))
            
            # สร้าง Row มาตรฐาน 3 คอลัมน์
            row = {
                "ingest_timestamp": current_time,
                "source_type": source_type,      # เช่น nova, orion
                "payload": json.dumps(item)      # เก็บ JSON ทั้งก้อนเป็น String
            }
            rows_to_insert.append(row)

        # 4. ยิงเข้า BigQuery
        if rows_to_insert:
            errors = bq_client.insert_rows_json(TABLE_ID, rows_to_insert)
            if errors == []:
                print(f"Successfully ingested {len(rows_to_insert)} raw events.")
            else:
                print(f"Encountered errors: {errors}")
                raise RuntimeError(f"BigQuery Insert Errors: {errors}")

    except Exception as e:
        print(f"Critical Error: {e}")
        # (Optional) ใน Production ควรส่ง Alert เข้า Slack/Email ตรงนี้
        raise e