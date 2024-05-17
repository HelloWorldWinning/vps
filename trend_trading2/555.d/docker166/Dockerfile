# Use an official lightweight Python image.
# python:3.9-slim is a good choice for a balance between size and usability.
#FROM python:3.9-slim
FROM python:3.9.15-alpine

# Set the working directory in the container
WORKDIR /usr/src/app
#WORKDIR /data

# Copy the requirements file into the container at /usr/src/app
COPY requirements.txt ./

# Install any needed packages specified in requirements.txt
# We are not directly adding flask, markdown2, and flask_httpauth 
# here because they will be included in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the current directory contents into the container at /usr/src/app
COPY . .

# Make port 80 available to the world outside this container
# Assuming that your flask app is using the default port of 5000
EXPOSE 166

# Define environment variable
ENV FLASK_APP=jupyter166.py

# Run python command when the container launches
CMD ["python", "jupyter166.py"]
