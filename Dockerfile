# Use official Python base image
FROM python:3.13-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the current directory content into the container
COPY . /app

# Install any dependencies defined in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Expose the port the app will run on
EXPOSE 80

# Command to run the Flask app
CMD ["python", "app.py"]
