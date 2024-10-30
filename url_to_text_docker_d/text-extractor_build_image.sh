#!/bin/bash
# Script to create a Dockerfile and build a self-contained Docker image
# Tag the image as oklove/text-extractor

# Step 1: Create the Dockerfile with all necessary files embedded
cat > Dockerfile << 'EOF'
# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory to /app
WORKDIR /app

# Create requirements.txt inside the container with specific versions
RUN echo "Flask==2.0.1\nWerkzeug==2.0.1\nrequests==2.26.0" > requirements.txt

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create app.py inside the container
RUN echo 'from flask import Flask, request\n\
app = Flask(__name__)\n\
\n\
@app.route("/")\n\
def hello():\n\
    return "Text Extractor Service is running!"\n\
\n\
@app.route("/extract", methods=["POST"])\n\
def extract_text():\n\
    try:\n\
        data = request.get_json()\n\
        if not data or "text" not in data:\n\
            return {"error": "No text provided"}, 400\n\
        return {"extracted": data["text"]}\n\
    except Exception as e:\n\
        return {"error": str(e)}, 500\n\
\n\
if __name__ == "__main__":\n\
    app.run(host="0.0.0.0", port=9977)' > app.py

# Expose port for the Flask app
EXPOSE 9977

# Set environment variables
ENV FLASK_APP=app.py
ENV FLASK_RUN_PORT=9977

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
    environment:
      - FLASK_APP=app.py
      - FLASK_RUN_PORT=9977
    restart: unless-stopped
EOF

echo "Created docker-compose.yml for reference"
echo "To run the container, use: docker compose up -d"
