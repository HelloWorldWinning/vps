from flask import Flask, render_template_string, request, Response, send_from_directory, abort, url_for
#from flask import Flask, render_template_string, request, Response, send_from_directory, abort
import markdown2
import os
from flask_httpauth import HTTPBasicAuth

app = Flask(__name__)
auth = HTTPBasicAuth()

MARKDOWN_DIR = '/'

users = {
    "1": "1"
}

@auth.verify_password
def verify_password(username, password):
    if username in users and users[username] == password:
        return username

def is_markdown_file(filename):
    return filename.endswith(('.md', '.markdown', '.mkd'))

def is_text_file(filename):
    return filename.endswith('.txt')

def is_image_file(filename):
    return filename.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.svg'))



@app.route('/')
@app.route('/<path:subpath>')
@auth.login_required
def list_files(subpath=''):
    current_dir = os.path.join(MARKDOWN_DIR, subpath)
    if not os.path.abspath(current_dir).startswith(MARKDOWN_DIR):
        return 'Unauthorized access', 403

    current_dir = os.path.normpath(current_dir)

    markdown_files = []
    text_files = []
    directories = []
    try:
        with os.scandir(current_dir) as entries:
            for entry in entries:
                if entry.is_file():
                    if is_markdown_file(entry.name):
                        markdown_files.append(entry.name)
                    elif is_text_file(entry.name):
                        text_files.append(entry.name)
                elif entry.is_dir():
                    directories.append(entry.name)
    except FileNotFoundError:
        return 'Directory not found', 404

    markdown_files.sort()
    text_files.sort()
    directories.sort()

    hostname = os.uname().nodename
    path_parts = subpath.split('/')
    path_links = []
    for i in range(len(path_parts)):
        if path_parts[i]:
            path = '/'.join(path_parts[:i+1])
            link = f'<a href="{url_for("list_files", subpath=path)}">{path_parts[i]}</a>'
            path_links.append(link)
    path_str = f'{hostname} /{"/".join(path_links)}'

    return render_template_string('''
        <!DOCTYPE html>
        <html>
        <head>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-mml-chtml.min.js" async></script>
            <title>Files and Directories</title>
            <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400&display=swap" rel="stylesheet">
            <style>
                body { font-family: 'Source Code Pro', monospace; }
                ul { list-style-type: none; padding: 0; }
                li { margin: 5px 0; }
                pre { background-color: #f4f4f4; padding: 10px; font-family: 'Source Code Pro', monospace; }
            </style>
        </head>
        <body>
            <p>{{ path_str|safe }}</p>
            <h2>Markdown:</h2>
            <ul>
                {% for file in markdown_files %}
                <li><a href="{{ url_for('serve_file', subpath=subpath, filename=file) }}">{{ file }}</a></li>
                {% endfor %}
            </ul>
            <h2>Text:</h2>
            <ul>
                {% for file in text_files %}
                <li><a href="{{ url_for('serve_file', subpath=subpath, filename=file) }}">{{ file }}</a></li>
                {% endfor %}
            </ul>
            <h2>Directories:</h2>
            <ul>
                {% for directory in directories %}
                <li><a href="{{ url_for('list_files', subpath=subpath + '/' + directory if subpath else directory) }}">{{ directory }}</a></li>
                {% endfor %}
            </ul>
        </body>
        </html>
    ''', markdown_files=markdown_files, text_files=text_files, directories=directories, subpath=subpath, path_str=path_str)





@app.route('/md/<path:subpath>/<filename>')
@auth.login_required
def serve_file(subpath, filename):
    file_path = os.path.join(MARKDOWN_DIR, subpath, filename)
    if not os.path.abspath(file_path).startswith(MARKDOWN_DIR):
        return "Unauthorized access", 403
    
    file_title, file_extension = os.path.splitext(filename)

    if is_markdown_file(filename) or is_text_file(filename):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                if is_text_file(filename):
                    content = '<pre>' + content + '</pre>'
                else:
                    # Convert checkbox syntax to HTML
                    content = content.replace('- [ ]', '<input type="checkbox" disabled>')
                    content = content.replace('- [x]', '<input type="checkbox" checked disabled>')
                    content = markdown2.markdown(content, extras=["fenced-code-blocks"])
                full_html = f'''
                    <!DOCTYPE html>
                    <html>
                    <head>
                        <script src="https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-mml-chtml.min.js" async></script>
                        <title>{file_title}</title>
                        <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap" rel="stylesheet">
                        <style>
                            @font-face {{
                                font-family: 'FZFangJunHeiS';
                                src: url('https://github.com/HelloWorldWinning/vps/raw/main/folder_font_test/FZFangJunHeiS/FZFangJunHeiS_Regular.ttf') format('truetype');
                            }}
                            body {{ font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace; }}
                            pre {{ background-color: #ffffff; font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace; white-space: pre-wrap; word-wrap: break-word; }}
                            img, pre, table {{ max-width: 100%; overflow-x: auto; }}
                        </style>
                    </head>
                    <body>{content}</body>
                    </html>
                '''
                return Response(full_html, mimetype='text/html')
        except FileNotFoundError:
            return "File not found", 404
    elif is_image_file(filename):
        return send_from_directory(os.path.dirname(file_path), filename)
    else:
        return abort(404)



if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=155)
