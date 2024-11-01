# Use Python 3.9 slim as base image
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# Install required packages and clean up
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc python3-dev && \
    pip install --no-cache-dir -r requirements.txt && \
    apt-get remove -y gcc python3-dev && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy application files
COPY token_counter.py .
COPY tokenizer_service.py .

# Create start script with proper line endings
RUN echo '#!/bin/sh' > start.sh && \
    echo 'python3 tokenizer_service.py &' >> start.sh && \
    echo 'python3 token_counter.py' >> start.sh && \
    chmod +x start.sh

# Expose ports
EXPOSE 6868 6969

# Set the shell as entrypoint
ENTRYPOINT ["/bin/sh", "./start.sh"]
