# Use Python 3.9 slim image as base
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY . .

# Create static directory if it doesn't exist
RUN mkdir -p static

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV MODULE_NAME=main
ENV VARIABLE_NAME=app
ENV PORT=187

# Expose port 187
EXPOSE 187

# Command to run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "187"]
