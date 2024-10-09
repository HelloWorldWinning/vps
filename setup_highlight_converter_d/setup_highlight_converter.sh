#!/bin/bash

# Step 1: Create the directory for the server
mkdir -p /data/highlight_converter_187

# Step 2: Change directory
cd /data/highlight_converter_187

# Step 3: Get the current Python environment
PYTHON_PATH=$(which python)

# Step 4: Create the Python file with the Flask server code
cat << "EOF" > highlight_conversion_service.py
from flask import Flask, request, jsonify, send_file
import pandas as pd
from datetime import datetime
import os
import json

app = Flask(__name__)

# Function to convert the JSON file to the CSV format
def convert_json_to_csv(json_data, output_path, title_name):
    csv_data_final_update_empty_url = []

    annotations = json_data.get('annotations', [])

    for annotation in annotations:
        # Format the timestamp to "YYYY-MM-DD HH:MM:SS"
        timestamp = annotation.get("timestamp")
        formatted_date = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%S.%fZ").strftime("%Y-%m-%d %H:%M:%S")

        # Use spine_index for Location and leave URL empty
        location = annotation.get("spine_index", "")

        # Append the reformatted data
        csv_data_final_update_empty_url.append({
            "Highlight": annotation.get("highlighted_text"),
            "Title": title_name,  # Use the dynamic title name
            "Author": "",
            "URL": "",  # Leave URL empty
            "Note": annotation.get("notes", ""),
            "Location": location,
            "Date": formatted_date
        })

    # Create a DataFrame and save it as CSV with the updated structure
    df_final_update_empty_url = pd.DataFrame(csv_data_final_update_empty_url)
    df_final_update_empty_url = df_final_update_empty_url[['Highlight', 'Title', 'Author', 'URL', 'Note', 'Location', 'Date']]

    # Save the CSV with the title-based name
    df_final_update_empty_url.to_csv(output_path, index=False, encoding='utf-8')

# Route to display the upload form with auto-submit
@app.route('/')
def upload_form():
    return '''
        <html>
        <body>
            <h1>Select JSON file to Convert to CSV</h1>
            <form method="POST" enctype="multipart/form-data" action="/upload" id="uploadForm">
                <input type="file" name="file" onchange="document.getElementById('uploadForm').submit();"><br><br>
            </form>
            <script>
                // Automatically submit the form when a file is selected
                document.querySelector('input[type="file"]').addEventListener('change', function() {
                    document.getElementById('uploadForm').submit();
                });
            </script>
        </body>
        </html>
    '''

# Route to handle file upload and conversion
@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400
    file = request.files['file']

    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    if file:
        # Load JSON from the file
        json_data = json.load(file)

        # Extract title name either from the file or from the JSON (if present)
        title_name = json_data.get("title", file.filename.split('.')[0])

        # Generate the output CSV file name using the title
        output_csv = f'converted_highlights_{title_name}.csv'

        # Convert the JSON data to CSV
        convert_json_to_csv(json_data, output_csv, title_name)

        # Send the file for download
        return send_file(output_csv, as_attachment=True)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=187)
EOF

# Step 5: Install necessary Python packages
$PYTHON_PATH -m pip install flask pandas

# Step 6: Create the systemd service file for the server
cat << EOF > /etc/systemd/system/highlight_converter_187.service
[Unit]
Description=Highlight Converter Flask Service
After=network.target

[Service]
User=root
WorkingDirectory=/data/highlight_converter_187
ExecStart=$PYTHON_PATH /data/highlight_converter_187/highlight_conversion_service.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Step 7: Reload systemctl, enable and start the service
systemctl daemon-reload
systemctl enable highlight_converter_187
systemctl start highlight_converter_187

# Step 8: Check the status of the service
systemctl status highlight_converter_187 --no-pager

echo "Flask server setup and started successfully!"

