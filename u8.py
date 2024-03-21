import os
from flask import Flask, request, redirect, render_template_string, Response
from werkzeug.utils import secure_filename
from functools import wraps

app = Flask(__name__)

# Default upload directory and credentials
DEFAULT_UPLOAD_FOLDER = '/data/upload_folder'
USERNAME = 'admin'
PASSWORD = 'password'
os.makedirs(DEFAULT_UPLOAD_FOLDER, exist_ok=True)

def check_auth(username, password):
    return username == USERNAME and password == PASSWORD

def authenticate():
    return Response(
    'Could not verify your access level for that URL.\n'
    'You have to login with proper credentials', 401,
    {'WWW-Authenticate': 'Basic realm="Login Required"'})

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated

@app.route('/')
@requires_auth
def index():
    html_content = '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Upload File or Folder</title>
        <script>
        function uploadFiles() {
            document.getElementById('uploadForm').submit();
            document.getElementById('loading').style.display = 'block';
            document.getElementById('uploadButton').disabled = true;
            document.getElementById('folderButton').disabled = true;
        }

        function triggerFileUpload() {
            document.getElementById('fileInput').click();
        }

        function triggerFolderUpload() {
            document.getElementById('folderInput').click();
        }
        </script>
    </head>
    <body>
        <h1>Upload File or Folder</h1>
        <form id="uploadForm" action="/upload" method="post" enctype="multipart/form-data">
            <label for="path">Upload Path:</label>
            <input type="text" name="path" id="path" value="/data/upload_folder">
            <input type="file" id="fileInput" name="files" multiple style="display: none;" onchange="uploadFiles()">
            <input type="file" id="folderInput" name="files" multiple webkitdirectory style="display: none;" onchange="uploadFiles()">
            <button type="button" id="uploadButton" onclick="triggerFileUpload()">Choose Files</button>
            <button type="button" id="folderButton" onclick="triggerFolderUpload()">Choose Folder</button>
            <div id="loading" style="display: none;">Uploading, please wait...</div>
        </form>
    </body>
    </html>
    '''
    return render_template_string(html_content)

@app.route('/upload', methods=['POST'])
@requires_auth
def upload_file():
    base_upload_path = request.form.get('path') or DEFAULT_UPLOAD_FOLDER

    files = request.files.getlist('files')
    if not files:
        return 'No files selected for upload.'

    for file in files:
        if file.filename == '':
            continue

        relative_path = '/'.join([secure_filename(part) for part in file.filename.split('/')])
        save_path = os.path.join(base_upload_path, relative_path)

        os.makedirs(os.path.dirname(save_path), exist_ok=True)
        file.save(save_path)

    return f'Files uploaded successfully to {base_upload_path}'

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=777)

