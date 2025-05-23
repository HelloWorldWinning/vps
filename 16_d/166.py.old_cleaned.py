from flask import Flask, render_template_string, request, session, redirect, url_for
import nbformat
import nbconvert
import os
from datetime import datetime
from pygments import highlight
from pygments.lexers import PythonLexer
from pygments.formatters import HtmlFormatter
from pygments.styles import get_style_by_name
from flask import send_from_directory
from datetime import timedelta

style_name = "manni"
app = Flask(__name__)
app.secret_key = "a"
app.config["PERMANENT_SESSION_LIFETIME"] = timedelta(days=7)
background_color_hex = "#154659"


@app.route("/favicon.ico")
def favicon():
    return redirect(
        "https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_files/my_logo/favicon.ico",
        code=302,
    )


def human_readable_size(size, decimal_places=2):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024.0:
            break
        size /= 1024.0
    return f"{size:.{decimal_places}f} {unit}"


def list_files_and_dirs(path):
    items = []
    for item in os.listdir(path):
        if item.startswith("."):
            continue
        if (
            item.endswith(".ipynb")
            or item.endswith(".py")
            or os.path.isdir(os.path.join(path, item))
        ):
            full_path = os.path.join(path, item)
            size = human_readable_size(os.path.getsize(full_path))
            modified_time = datetime.fromtimestamp(
                os.path.getmtime(full_path)
            ).strftime("%Y-%m-%d %H:%M:%S")
            items.append((full_path, size, modified_time))
    sorted_items = sorted(items, key=lambda x: x[0])
    return enumerate(sorted_items, start=1)


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        if request.form["password"] == "a":
            session["logged_in"] = True
            return redirect(url_for("root"))
    return """
        <style>
            .center {
                position: absolute;
                top: 50%;
                left: 50%;
                transform: translate(-50%, -50%);
                text-align: center;
            }
        </style>
        <div class="center">
            <form method="post">
                <p><input type=password name=password>
                <p><input type=submit value=Login>
            </form>
        </div>
    """


@app.route("/<path:subpath>")
def navigate(subpath):
    if not session.get("logged_in"):
        return redirect(url_for("login"))
    path = "/" + subpath
    files_and_dirs = list_files_and_dirs(path)
    hostname = os.uname().nodename
    path_parts = subpath.split("/")
    path_links = []
    for i in range(len(path_parts)):
        if path_parts[i]:
            path = "/".join(path_parts[: i + 1])
            link = f'<a href="{url_for("navigate", subpath=path)}">{path_parts[i]}</a>'
            path_links.append(link)
    path_str = f'{hostname} /{"/".join(path_links)}'
    custom_css = (
        'body * , pre { font-family: "Source Code Pro", monospace  !important ; }'
    )
    return render_template_string(
        """
        <html>
        <head>
            <title>{{ '/' + subpath + '/' }}</title>
            <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap" rel="stylesheet">
            <style>
            a {  text-decoration: none; }
                table {
                    border-collapse: collapse;
                    width: 100%;
                }
                th, td {
                    border: 1px solid black;
                    padding: 10px;
                    text-align: center;
                }
                th {
                    background-color: #f2f2f2;
                }
                .item-col {
                    text-align: left;
                }
            </style>
        <style>body, pre { font-family: "Source Code Pro", monospace  !important ; }</style>
        </head>
        <body>
            <p>{{ path_str|safe }}</p>
            <table>
                <tr>
                    <th>No</th>
                    <th class="item-col">Item</th>
                    <th>Size</th>
                    <th>Modified</th>
                </tr>
                {% for idx, (item, size, modified_time) in files_and_dirs %}
                    <tr>
                        <td>{{ idx }}</td>
                        {% if item.endswith('.ipynb') %}
                            <td class="item-col"><a href="{{ url_for('notebooks', path=item[1:]) }}">{{ item.split('/')[-1] }}</a></td>
                        {% elif item.endswith('.py') %}
                            <td class="item-col"><a href="{{ url_for('python_files', path=item[1:]) }}">{{ item.split('/')[-1] }}</a></td>
                        {% else %}
                            <td class="item-col"><a href="{{ url_for('navigate', subpath=item[1:]) }}">{{ item.split('/')[-1] }}</a></td>
                        {% endif %}
                        <td>{{ size }}</td>
                        <td>{{ modified_time }}</td>
                    </tr>
                {% endfor %}
            </table>
        </body>
        </html>
    """,
        subpath=subpath,
        files_and_dirs=files_and_dirs,
        path_str=path_str,
    )


@app.route("/python/<path:path>")
@app.route("/python_files/<path:path>")
@app.route("/py/<path:path>")
def python_files(path):
    if not session.get("logged_in"):
        return redirect(url_for("login"))
    file_path = "/" + path
    if file_path.endswith(".py"):
        with open(file_path, "r") as file:
            content = file.read()
            lexer = PythonLexer()
            style = get_style_by_name(style_name)
            formatter = HtmlFormatter(linenos=True, style=style)
            highlighted_code = highlight(content, lexer, formatter)
            custom_css = """html *, pre { font-family: "Source Code Pro", monospace  !important ; }
                           .linenodiv { color: #bbb !important; }"""
            return f'<html><head><title>{os.path.basename(file_path)}</title><link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap" rel="stylesheet"><style>{formatter.get_style_defs()}</style><style>{custom_css}</style></head><body style="background-color: {style.background_color};">{highlighted_code}</body></html>'
    else:
        return navigate(path)


@app.route("/ipynb/<path:path>")
@app.route("/nb/<path:path>")
@app.route("/notebook/<path:path>")
@app.route("/notebooks/<path:path>")
def notebooks(path):
    if not session.get("logged_in"):
        return redirect(url_for("login"))
    notebook_path = "/" + path
    if notebook_path.endswith(".ipynb"):
        filename = os.path.basename(notebook_path)
        with open(notebook_path, "r") as file:
            notebook_content = nbformat.read(file, as_version=4)
            html_exporter = nbconvert.HTMLExporter()
            (body, resources) = html_exporter.from_notebook_node(notebook_content)
            custom_css = 'html *, pre { font-family: "Source Code Pro", monospace  !important ; }'
            return f'<html><head><title>{filename}</title><link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap" rel="stylesheet"><style>{custom_css}</style></head><body>{body}</body></html>'
    elif notebook_path.endswith(".py"):
        with open(notebook_path, "r") as file:
            content = file.read()
            lexer = PythonLexer()
            style = get_style_by_name(style_name)
            formatter = HtmlFormatter(style=style)
            highlighted_code = highlight(content, lexer, formatter)
            custom_css = 'html *, pre { font-family: "Source Code Pro", monospace  !important ; }'
            return f'<html><head><title>{os.path.basename(notebook_path)}</title><link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap" rel="stylesheet"><style>{formatter.get_style_defs()}</style><style>{custom_css}</style></head><body style="background-color: {style.background_color};">{highlighted_code}</body></html>'
    else:
        return navigate(path)


@app.route("/tree/<path:path>")
def tree(path):
    if not session.get("logged_in"):
        return redirect(url_for("login"))
    notebook_path = "/" + path
    if notebook_path.endswith(".ipynb"):
        filename = os.path.basename(notebook_path)
        with open(notebook_path, "r") as file:
            notebook_content = nbformat.read(file, as_version=4)
            html_exporter = nbconvert.HTMLExporter()
            (body, resources) = html_exporter.from_notebook_node(notebook_content)
            custom_css = 'html * , pre { font-family: "Source Code Pro", monospace  !important ; }'
            return f'<html><head><title>{filename}</title><link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600&display=swap" rel="stylesheet"><style>{custom_css}</style></head><body>{body}</body></html>'
    else:
        return navigate(path)


@app.route("/")
def root():
    if not session.get("logged_in"):
        return redirect(url_for("login"))
    return navigate("")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=166)
