#!/bin/bash
# Script to create a Dockerfile and build a self-contained Docker image
# Tag the image as oklove/text-extractor

# Step 1: Create the Dockerfile
cat > Dockerfile << 'EOF'
# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory to /app
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY . /app

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose port for the Flask app
EXPOSE 9977

# Run app.py when the container launches
CMD ["python", "app.py"]
EOF

# Step 2: Build the Docker image and tag it
echo "Building Docker image..."
docker build -t oklove/text-extractor .
echo "Docker image 'oklove/text-extractor' built successfully."

# Step 3: Create a sample docker-compose.yml for reference
cat > docker-compose.yml << 'EOF'
version: '3'
services:
  text-extractor:
    image: oklove/text-extractor
    network_mode: "host"
    restart: unless-stopped
EOF

echo "Created docker-compose.yml for reference"
echo "To run the container, use: docker compose up -d"

