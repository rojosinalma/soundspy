FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY threshold_monitor.py .

CMD ["python", "threshold_monitor.py"]

