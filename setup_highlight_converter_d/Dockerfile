# Use the specified base image
FROM python:3.9.15-alpine

# Install Python dependencies
RUN pip install --no-cache-dir numpy pandas flask

# Set the working directory
WORKDIR /app

# Copy the Flask application into the container
COPY highlight_conversion_service.py .

# Expose port 187
EXPOSE 187

# Run the Flask application
CMD ["python", "highlight_conversion_service.py"]
