# marketplace/Dockerfile
FROM python:3.13-slim

WORKDIR /app

# copy requirements first -> for better caching
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# copy sorce code
COPY . .

# Flask will listen on port 5000
ENV FLASK_APP=marketplace.py
ENV FLASK_RUN_HOST=0.0.0.0
ENV FLASK_RUN_PORT=5000

# RECOMMENDATIONS_HOST WILL BE SET IN K8S
EXPOSE 5000

CMD ["flask", "run"]
