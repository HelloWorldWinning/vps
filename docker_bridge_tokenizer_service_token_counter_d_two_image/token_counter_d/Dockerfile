# token_counter/Dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY token_counter.py .
EXPOSE 6868
CMD ["python3", "token_counter.py"]

