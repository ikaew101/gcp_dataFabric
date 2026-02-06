# ใช้ Python Image ตัวเล็กสุด เพื่อให้ Build ไวๆ
FROM python:3.10-slim

# ตั้งค่าให้ Python แสดงผล Log ทันที (ไม่เก็บ Buffer) จะได้เห็น Log ไวๆ
ENV PYTHONUNBUFFERED True

# ตั้งค่าโฟลเดอร์ทำงานข้างใน Container
ENV APP_HOME /app
WORKDIR $APP_HOME

# Copy รายชื่อ Library ไปก่อน (เพื่อให้ Docker จำ Cache ได้ ไม่ต้องโหลดใหม่ทุกรอบ)
COPY requirements.txt .

# ติดตั้ง Library
RUN pip install --no-cache-dir -r requirements.txt

# Copy โค้ดทั้งหมดในโฟลเดอร์ backend_source เข้าไป
COPY . ./

# คำสั่งรัน Server (ใช้ gunicorn เพื่อความเสถียร)
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app