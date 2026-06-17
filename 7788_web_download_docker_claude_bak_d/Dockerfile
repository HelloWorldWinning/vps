FROM python:3.10.15-slim-bookworm

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 💡 Ensure UTF-8 locale inside the container
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONUTF8=1
ENV PYTHONIOENCODING=utf-8

# Create app and mount directories
RUN mkdir -p /app/Host

WORKDIR /app

COPY requirements.txt .
COPY main.py .

RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

EXPOSE 7788

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7788", "--reload"]

