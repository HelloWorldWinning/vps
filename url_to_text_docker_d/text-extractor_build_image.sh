#!/bin/bash

# Script to create a Dockerfile and build a Docker image
# Tag the image as oklove/text-extractor

# Step 1: Create the Dockerfile
cat > Dockerfile << 'EOF'
# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory to /app
WORKDIR /app

# Copy requirements.txt first to leverage Docker cache
COPY requirements.txt ./

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code
COPY . .

# Expose port 5000 for the Flask app
EXPOSE 9977

# Define environment variable
ENV FLASK_APP=app.py

# Run app.py when the container launches
CMD ["flask", "run", "--host=0.0.0.0"]
EOF

# Step 2: Create requirements.txt if it doesn't exist
if [ ! -f requirements.txt ]; then
    cat > requirements.txt << 'EOF'
Flask
requests
EOF
    echo "Created requirements.txt with default dependencies."
fi

# Step 3: Build the Docker image and tag it
echo "Building Docker image..."
docker build -t oklove/text-extractor .

echo "Docker image 'oklove/text-extractor' built successfully."

