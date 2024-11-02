# tokenizer_service/Dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY tokenizer_service.py .
EXPOSE 6969
CMD ["python3", "tokenizer_service.py"]

