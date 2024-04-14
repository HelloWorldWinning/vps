from flask import Flask, render_template_string, request, Response, send_from_directory, abort
import markdown2
import os

app = Flask(__name__)

# Define the base directory from where markdown files can be accessed
MARKDOWN_DIR = '/'

def is_markdown_file(filename):
    """Check if a file is a markdown file by its extension."""
    return filename.endswith(('.md', '.markdown', '.mkd'))

def is_image_file(filename):
    """Check if a file is an image by its extension."""
    return filename.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.svg'))

@app.route('/')
@app.route('/<path:subpath>')
def list_markdown_files(subpath=''):
    """List all files and directories in the specified path."""
    current_dir = os.path.join(MARKDOWN_DIR, subpath)
    if not os.path.abspath(current_dir).startswith(MARKDOWN_DIR):
        return 'Unauthorized access', 403

    current_dir = os.path.normpath(current_dir)

    files = []
    directories = []
    try:
        with os.scandir(current_dir) as entries:
            for entry in entries:
                if entry.is_file() and (is_markdown_file(entry.name) or is_image_file(entry.name)):
                    files.append(entry.name)
                elif entry.is_dir():
                    directories.append(entry.name)
    except FileNotFoundError:
        return 'Directory not found', 404

    files.sort()
    directories.sort()

    filename = request.args.get('filename')
    return render_template_string('''
        <h2>Files:</h2>
        <ul>
            {% for file in files %}
            <li style="font-size: 160%;" ><a href="{{ url_for('serve_file', subpath=subpath, filename=file) }}">{{ file }}</a></li>
            {% endfor %}
        </ul>
        <h2>Directories:</h2>
        <ul>
            {% for directory in directories %}
            <li style="font-size: 130%;"><a href="{{ url_for('list_markdown_files', subpath=subpath + '/' + directory if subpath else directory) }}">{{ directory }}</a></li>
            {% endfor %}
        </ul>
    ''', files=files, directories=directories, subpath=subpath, filename=filename)


@app.route('/md/<path:subpath>/<filename>')
def serve_file(subpath, filename):
    """Serve a file, either as markdown-rendered HTML or as binary data."""
    file_path = os.path.join(MARKDOWN_DIR, subpath, filename)
    if not os.path.abspath(file_path).startswith(MARKDOWN_DIR):
        return "Unauthorized access", 403
    
    if is_markdown_file(filename):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                html = markdown2.markdown(content, extras=["fenced-code-blocks"])
                full_html = f'''
                    <!DOCTYPE html>
                    <html>
                    <head>
                        <title>Markdown Preview</title>
                        <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap" rel="stylesheet">
                        <style>
                            body {{ font-family: 'Source Code Pro', monospace; }}
                            pre {{ background-color: #f4f4f4; padding: 10px; }}
                        </style>
                    </head>
                    <body>{html}</body>
                    </html>
                '''
                return Response(full_html, mimetype='text/html')
        except FileNotFoundError:
            return "File not found", 404
    elif is_image_file(filename):
        return send_from_directory(os.path.dirname(file_path), filename)
    else:
        return abort(404)  # Not found for non-handled file types

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=155)

