FROM python:3.10.15-slim-bookworm

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Create app and mount directories
RUN mkdir -p /app/Host

WORKDIR /app

COPY requirements.txt .
COPY main.py .

RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

EXPOSE 7788

# Modified command to use proper import string
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7788", "--reload"]
