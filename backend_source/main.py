import os
import sqlalchemy
from flask import Flask, request, jsonify
from datetime import datetime

app = Flask(__name__)

# ตั้งค่า Database Connection
def connect_tcp_socket():
    db_user = os.environ["DB_USER"]
    db_pass = os.environ["DB_PASS"]
    db_name = os.environ["DB_NAME"]
    db_conn_name = os.environ["INSTANCE_CONNECTION_NAME"]

    # สำหรับ Cloud Run เชื่อมต่อผ่าน Unix Socket
    # แต่ถ้า test Local ต้องแก้ logic ตรงนี้เพิ่ม (ในที่นี้เน้น Cloud Run)
    pool = sqlalchemy.create_engine(
        sqlalchemy.engine.url.URL.create(
            drivername="postgresql+pg8000",
            username=db_user,
            password=db_pass,
            database=db_name,
            query={"unix_sock": f"/cloudsql/{db_conn_name}/.s.PGSQL.5432"}
        )
    )
    return pool

db = connect_tcp_socket()

# สร้าง Table อัตโนมัติถ้ายังไม่มี
def init_db():
    with db.connect() as conn:
        conn.execute(sqlalchemy.text(
            "CREATE TABLE IF NOT EXISTS sensor_data ("
            "id SERIAL PRIMARY KEY, "
            "source VARCHAR(50), "
            "device_id VARCHAR(50), "
            "payload JSONB, "
            "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
            ");"
        ))
        conn.commit()

# รันคำสั่งสร้าง Table ตอนเริ่ม App
try:
    init_db()
    print("Database initialized successfully.")
except Exception as e:
    print(f"DB Init Error: {e}")

@app.route("/")
def hello():
    return "Sensor API Backend is Running with Cloud SQL!"

@app.route("/ingest", methods=['POST'])
def ingest():
    try:
        data = request.json
        if not data:
            return jsonify({"error": "No JSON data"}), 400
            
        # รองรับทั้งแบบ Single Object และ List
        items = data if isinstance(data, list) else [data]
        
        with db.connect() as conn:
            for item in items:
                source = item.get('source', 'unknown')
                device_id = item.get('device_id', 'unknown')
                
                # Insert ลง Database
                conn.execute(
                    sqlalchemy.text(
                        "INSERT INTO sensor_data (source, device_id, payload) VALUES (:s, :d, :p)"
                    ),
                    {"s": source, "d": device_id, "p": str(item).replace("'", '"')} 
                    # หมายเหตุ: payload เก็บเป็น JSONB หรือ String ก็ได้
                )
            conn.commit()
            
        return jsonify({"status": "success", "count": len(items)}), 200

    except Exception as e:
        print(f"Error: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))