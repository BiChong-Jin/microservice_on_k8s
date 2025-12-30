# recommendations/Dockerfile
FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# grpc server listen on 50051
EXPOSE 50051

CMD["python", "recommendations.py"]
