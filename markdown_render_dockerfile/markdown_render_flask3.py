from flask import Flask, render_template_string, request, Response, send_from_directory, abort, url_for
import markdown2
import markdown
import os
from flask_httpauth import HTTPBasicAuth
from markdown.extensions import Extension
from markdown.preprocessors import Preprocessor
from markdown.inlinepatterns import InlineProcessor
from xml.etree import ElementTree as etree


app = Flask(__name__)
auth = HTTPBasicAuth()

MARKDOWN_DIR = '/'

username = os.getenv('USERNAME')
password = os.getenv('PASSWORD')

# Check if username and password are provided
if username and password:
    users = {username: password}
else:
    users = {"a": "a"}  # Default users if username and password





class StrikethroughExtension(Extension):
    def extendMarkdown(self, md):
        md.inlinePatterns.register(StrikethroughInlineProcessor(r'~~(.+?)~~'), 'strikethrough', 175)

class StrikethroughInlineProcessor(InlineProcessor):
    def handleMatch(self, m, data):
        el = etree.Element('del')
        el.text = m.group(1)
        return el, m.start(0), m.end(0)

class CheckboxPreprocessor(Preprocessor):
    def run(self, lines):
        new_lines = []
        for line in lines:
            line = line.replace('- [ ]', '<input type="checkbox" disabled>')
            line = line.replace('- [x]', '<input type="checkbox" checked disabled>')
            new_lines.append(line)
        return new_lines

class CheckboxExtension(Extension):
    def extendMarkdown(self, md):
        md.preprocessors.register(CheckboxPreprocessor(), 'checkbox', 25)






@auth.verify_password
def verify_password(username, password):
    if username in users and users[username] == password:
        return username

def is_markdown_file(filename):
    return filename.endswith(('.md','.mdx' ,'.markdown', '.mkd'))

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
            <!-- ... -->
            <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap" rel="stylesheet">
            <link rel="icon" href="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_files/my_logo/favicon.ico" type="image/x-icon">
            <style>
                @font-face {
                    font-family: 'FZFangJunHeiS';
                    src: url('https://github.com/HelloWorldWinning/vps/raw/main/folder_font_test/FZFangJunHeiS/FZFangJunHeiS_Regular.ttf') format('truetype');
                }
                body { font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace; }
                pre { background-color: #ffffff; font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace; white-space: pre-wrap; word-wrap: break-word; }
                .card-container {
                    display: flex;
                    flex-wrap: wrap;
                    justify-content: space-between;
                }
                .card {
                    width: 30%;
                    padding: 10px;
                    margin-bottom: 20px;
                    border: 1px solid #ccc;
                    border-radius: 5px;
                }

                .card li {
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }

                a {     text-decoration: none; }

            </style>
        </head>
        <body>
            <p>{{ path_str|safe }}</p>
            <div class="card-container">
                <div class="card">
                    <h3>Directories:</h3>
                    <ol>
                        {% for directory in directories %}
                        <li><a href="{{ url_for('list_files', subpath=subpath + '/' + directory if subpath else directory) }}">{{ directory }}</a></li>
                        {% endfor %}
                    </ol>
                </div>
                <div class="card">
                    <h3>Markdown:</h3>
                    <ol>
                        {% for file in markdown_files %}
                        <li><a href="{{ url_for('serve_file', subpath=subpath, filename=file) }}">{{ file }}</a></li>
                        {% endfor %}
                    </ol>
                </div>
                <div class="card">
                    <h3>Text:</h3>
                    <ol>
                        {% for file in text_files %}
                        <li><a href="{{ url_for('txt_file', subpath=subpath, filename=file) }}">{{ file }}</a></li>
                        {% endfor %}
                    </ol>
                </div>
            </div>
        </body>
        </html>
    ''', markdown_files=markdown_files, text_files=text_files, directories=directories, subpath=subpath, path_str=path_str)


@app.route('/markdown/<path:subpath>/<filename>')
@app.route('/md/<path:subpath>/<filename>')
@auth.login_required
def serve_file(subpath, filename):
    file_path = os.path.join(MARKDOWN_DIR, subpath, filename)
    if not os.path.abspath(file_path).startswith(MARKDOWN_DIR):
        return "Unauthorized access", 403

    file_title, file_extension = os.path.splitext(filename)

    if is_markdown_file(filename):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                content = markdown.markdown(content, extensions=[
                    CheckboxExtension(),
                    'toc',
                    'fenced_code',
                    'tables',
                    StrikethroughExtension()
                ])

                content = content.replace('- [ ]', '<input type="checkbox" disabled>')
                content = content.replace('- [x]', '<input type="checkbox" checked disabled>')
                full_html = f'''
    <!DOCTYPE html>
    <html>
    <head>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-mml-chtml.min.js" async></script>
        <title>{file_title}</title>

        <link href="https://fonts.googleapis.com/css2?family=Roboto+Mono:ital,wght@0,100..700;1,100..700&display=swap" rel="stylesheet">
        <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap" rel="stylesheet">
        <link rel="icon" href="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_files/my_logo/favicon.ico" type="image/x-icon">
        <style>
            @font-face {{
                font-family: 'FZFangJunHeiS';
                src: url('https://github.com/HelloWorldWinning/vps/raw/main/folder_font_test/FZFangJunHeiS/FZFangJunHeiS_Regular.ttf') format('truetype');
            }}
            body {{
                  font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace;
            padding: 20px;
            line-height: 1.6;
            text-align: justify;
            text-justify: inter-word;
                  }}
            pre {{
            background-color: #ffffff;
                font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace;
                white-space: pre-wrap;
                word-wrap: break-word;

                text-align: justify;
                text-justify: inter-word;
            }}

            img, pre, table {{ max-width: 100%; overflow-x: auto; }}

            /* TOC styles */
            .toc {{
                background-color: #f9f9f9;
                border: 1px solid #ccc;
                padding: 10px;
                margin-bottom: 20px;
            }}
            .toc ul {{
                list-style-type: none;
                padding-left: 20px;
            }}
            .toc li {{
                margin-bottom: 5px;
            }}
            .toc a {{
                text-decoration: none;
                color: #333;
            }}
            .toc a:hover {{
                text-decoration: underline;
            }}
   h1 {{
    color:   #ffffff;
    background-color:  #AC083F   ;
    padding: 5px 20px;
    border-radius: 5px;
    text-align: center;
    font-family: 'Roboto Mono', monospace;
    font-weight: 500 ;

    }}
        </style>
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

def is_text_file(filename):
    return filename.endswith('.txt')

@app.route('/text/<path:subpath>/<filename>')
@app.route('/txt/<path:subpath>/<filename>')
@auth.login_required
def txt_file(subpath, filename):
    file_path = os.path.join(MARKDOWN_DIR, subpath, filename)
    if not os.path.abspath(file_path).startswith(MARKDOWN_DIR):
        return "Unauthorized access", 403

    file_title, file_extension = os.path.splitext(filename)

    if is_text_file(filename):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                content = content.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
                content = '<pre>' + content + '</pre>'
                full_html = f'''
                    <!DOCTYPE html>
                    <html>
                    <head>
                        <title>{file_title}</title>
                        <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap" rel="stylesheet">
                        <link rel="icon" href="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_files/my_logo/favicon.ico" type="image/x-icon">
                        <style>
                            @font-face {{
                                font-family: 'FZFangJunHeiS';
                                src: url('https://github.com/HelloWorldWinning/vps/raw/main/folder_font_test/FZFangJunHeiS/FZFangJunHeiS_Regular.ttf') format('truetype');
                            }}
                            body {{
                                font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace;
                            line-height: 1.6;
                            padding: 25px;
                            white-space: pre-wrap;
                            word-wrap: break-word;
                            text-align: justify;
                            text-justify: inter-word;
                            }}

                            pre {{
                            background-color: #ffffff;
                            font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace;
                            white-space: pre-wrap;
                            word-wrap: break-word;

                            text-align: justify;
                            text-justify: inter-word;
                            }}
                        </style>
                    </head>
                    <body>{content}</body>
                    </html>
                '''
                return Response(full_html, mimetype='text/html')
        except FileNotFoundError:
            return "File not found", 404
    else:
        return abort(404)

if __name__ == '__main__':
    app.run(debug=False, host='0.0.0.0', port=177)

