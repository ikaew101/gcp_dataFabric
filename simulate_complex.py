import json
import time
from google.cloud import pubsub_v1
from datetime import datetime

# --- ตั้งค่าให้ตรงกับ Terraform ---
project_id = "cis-dev-ai-smart-mirror"  # Project ID ของคุณ
topic_id = "ingest_cis_datafabric"      # Topic Name จาก main.tf บรรทัดที่ 11

publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(project_id, topic_id)

def send_data(data):
    # แปลงข้อมูลเป็น JSON string และส่งเป็น bytes
    data_str = json.dumps(data)
    data_bytes = data_str.encode("utf-8")
    
    try:
        publish_future = publisher.publish(topic_path, data_bytes)
        # รอผลลัพธ์เพื่อความชัวร์
        print(f"Sent ({data.get('source', 'unknown')}): ID {publish_future.result()}")
    except Exception as e:
        print(f"Failed to send: {e}")

# จำลองข้อมูลจากหลายแหล่ง (Heterogeneous Data)
events = [
    # 1. NOVA: ส่ง temperature
    { "source": "nova", "device_id": "nova-001", "temperature": 36.5, "status": "active" },
    
    # 2. ORION: ส่ง speed และ location (คนละ parameter กันเลย)
    { "source": "orion", "device_id": "orion-99", "speed": 120, "lat": 13.75, "long": 100.50 },
    
    # 3. VIRGO: ส่งมาเป็น Array (Batch)
    [
        { "source": "virgo", "device_id": "virgo-A", "humidity": 60, "battery": 95 },
        { "source": "virgo", "device_id": "virgo-C", "humidity": 90, "battery": 90 },
        { "source": "virgo", "device_id": "virgo-B", "humidity": 62, "battery": 88 }
    ]
]

if __name__ == "__main__":
    print(f"Simulating data injection to {topic_path}...")
    
    # วนลูปส่งข้อมูล
    for event in events:
        send_data(event)
        time.sleep(1) # เว้นระยะนิดนึง
        
    print("Done! Please check BigQuery table 'raw_events'.")