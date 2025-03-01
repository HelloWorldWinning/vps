from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
import os
from urllib.parse import quote, unquote
import secrets
from datetime import datetime
import html
import nbformat
import nbconvert
from pygments import highlight
from pygments.lexers import get_lexer_by_name, guess_lexer_for_filename, TextLexer
from pygments.formatters import HtmlFormatter
from pygments.styles import get_style_by_name
from pygments.util import ClassNotFound

app = FastAPI()
security = HTTPBasic()

# Mount the static files directory to serve favicon.ico and other static files
app.mount("/static", StaticFiles(directory="."), name="static")


def authenticate(credentials: HTTPBasicCredentials = Depends(security)):
    correct_username = "a"
    correct_password = "a"

    is_correct_username = secrets.compare_digest(
        credentials.username.encode("utf8"), correct_username.encode("utf8")
    )
    is_correct_password = secrets.compare_digest(
        credentials.password.encode("utf8"), correct_password.encode("utf8")
    )

    if not (is_correct_username and is_correct_password):
        raise HTTPException(
            status_code=401,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials


def format_size(size_in_bytes: int) -> str:
    """Convert size in bytes to human readable format."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size_in_bytes < 1024.0:
            return f"{size_in_bytes:.1f} {unit}"
        size_in_bytes /= 1024.0
    return f"{size_in_bytes:.1f} PB"


def get_file_info(path: str) -> dict:
    """Get file/directory information including size and modification time."""
    stats = os.stat(path)
    return {
        "size": stats.st_size,
        "modified": datetime.fromtimestamp(stats.st_mtime).strftime(
            "%Y-%m-%d %H:%M:%S"
        ),
    }

def create_breadcrumb(path: str) -> str:
    """Create HTML breadcrumb navigation from path."""
    if path == "/Host":
        return '<a href="/" class="breadcrumb-item">/</a>'

    parts = path.split("/")
    breadcrumb_parts = []
    current_path = ""

    # Add root
    breadcrumb_parts.append('<a href="/" class="breadcrumb-item">/</a>')

    # Add each directory
    for part in parts:
        if part:  # Skip empty parts
            if not current_path and part == "Host":
                current_path = "/Host"
            else:
                current_path = os.path.join(current_path, part)

            encoded_path = quote(current_path.lstrip("/"))
            if part == "Host":
                # Skip showing "Host" in the breadcrumb
                continue
            breadcrumb_parts.append(
                f'<a href="/{encoded_path}" class="breadcrumb-item">{html.escape(part)}</a>/'
            )

    return "".join(breadcrumb_parts)


#def create_breadcrumb(path: str) -> str:
#    """Create HTML breadcrumb navigation from path."""
#    if path == "/Host":
#        return '<a href="/" class="breadcrumb-item">/</a>'
#
#    parts = path.split("/")
#    breadcrumb_parts = []
#    current_path = ""
#
#    # Add root
#    breadcrumb_parts.append('<a href="/" class="breadcrumb-item">/</a>')
#
#    # Add each directory
#    for part in parts:
#        if part:  # Skip empty parts
#            current_path = os.path.join(current_path, part)
#            encoded_path = quote(current_path.lstrip("/"))
#            breadcrumb_parts.append(
#                f'<a href="/{encoded_path}" class="breadcrumb-item">{html.escape(part)}</a>/'
#            )
#
#    return "".join(breadcrumb_parts)


# Mapping of file extensions to Pygments lexer names
LEXER_MAPPING = {
    ".py": "python",
    ".sh": "bash",
    ".c": "c",
    ".cpp": "cpp",
    ".java": "java",
    ".js": "javascript",
    ".css": "css",
    ".html": "html",
    ".htm": "html",
    ".json": "json",
    ".xml": "xml",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".md": "markdown",
    ".sql": "sql",
    ".rb": "ruby",
    ".go": "go",
    ".php": "php",
    ".rs": "rust",
    ".swift": "swift",
    ".txt": "text",
    ".bat": "bat",
    ".pl": "perl",
    ".pm": "perl",
    ".r": "r",
    ".ini": "ini",
    ".cfg": "ini",
    ".conf": "nginx",  # Use 'nginx' lexer for .conf files as a reasonable default
    ".coffee": "coffeescript",
    ".ts": "typescript",
    ".jsx": "jsx",
    ".tsx": "tsx",
    ".log": "text",
    ".csv": "csv",
    # Add more mappings as needed
}


@app.get("/", response_class=HTMLResponse)
async def root(
    request: Request, credentials: HTTPBasicCredentials = Depends(authenticate)
):
    return await navigate("", request, credentials)


@app.get("/{subpath:path}", response_class=HTMLResponse)
async def navigate(
    subpath: str,
    request: Request,
    credentials: HTTPBasicCredentials = Depends(authenticate),
):
    # Decode the subpath
    subpath = unquote(subpath)
    # Build the full path
  # full_path = os.path.normpath(os.path.join("/", subpath))
#   full_path = os.path.normpath(os.path.join("/", subpath))
    full_path = os.path.normpath(os.path.join("/Host", subpath))

    if not full_path.startswith("/Host"):
        raise HTTPException(status_code=404, detail="Path not found")

    if os.path.isdir(full_path):
        try:
            items = os.listdir(full_path)
        except PermissionError:
            raise HTTPException(status_code=403, detail="Permission denied")

        items.sort()

        # Create breadcrumb navigation
        breadcrumb = create_breadcrumb(full_path)

        # Prepare table rows
        table_rows = []

        # Add parent directory link if not in root
        if full_path != "/":
            parent_full_path = os.path.dirname(full_path)
            parent_rel_path = os.path.relpath(parent_full_path, "/Host")
            parent_url = quote(parent_rel_path)
            table_rows.append(
                f"""
                <tr>
                    <td>
                        <div class="item-container">
                            <span class="index-number">-</span>
                            <a href="/{parent_url}" class="folder">../</a>
                        </div>
                    </td>
                    <td class="size-col">-</td>
                    <td>-</td>
                </tr>
            """
            )

        # Add all directory contents
        idx = 1
        for item in items:
            if item.startswith("."):
                continue  # Skip hidden files

            item_full_path = os.path.join(full_path, item)
            item_rel_path = os.path.relpath(item_full_path, "/Host")
            item_url = quote(item_rel_path)

            if os.path.isdir(item_full_path):
                item_display = f"{item}/"
                item_class = "folder"
            else:
                item_display = item
                item_class = "file"

            try:
                item_info = get_file_info(item_full_path)
                item_modified = item_info["modified"]
                if os.path.isdir(item_full_path):
                    item_size = "-"
                else:
                    item_size = format_size(item_info["size"])
            except Exception:
                item_size = "-"
                item_modified = "-"

            table_rows.append(
                f"""
                <tr>
                    <td>
                        <div class="item-container">
                            <span class="index-number">{idx}.</span>
                            <a href="/{item_url}" class="{item_class}">{html.escape(item_display)}</a>
                        </div>
                    </td>
                    <td class="size-col">{item_size}</td>
                    <td>{item_modified}</td>
                </tr>
            """
            )
            idx += 1

        # Create HTML content with table and custom styling
        html_content = f"""
        <html>
        <head>
            <meta charset="UTF-8">
            <link rel="icon" href="/static/favicon.ico" sizes="any">
            <link rel="icon" type="image/x-icon" href="/static/favicon.ico">
            <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap" rel="stylesheet">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                @font-face {{
                    font-family: 'FZFangJunHeiS';
                    src: url('https://github.com/HelloWorldWinning/vps/raw/main/folder_font_test/FZFangJunHeiS/FZFangJunHeiS_Regular.ttf') format('truetype');
                }}

                html {{
                    zoom: 200%;
                }}

                body, html * {{
                    font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace;
                }}

                pre, pre * {{
                    font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace;
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }}

                body {{
                    margin: 20px;
                    background-color: #f8f9fa;
                }}

                .breadcrumb {{
                    background-color: white;
                    padding: 12px 15px;
                    margin-bottom: 20px;
                    border-radius: 4px;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                    font-size: 16px;
                    overflow-x: auto;
                    white-space: nowrap;
                }}

                .breadcrumb-item, .breadcrumb-item *, .breadcrumb > :not(a) {{
                    color: #1d910d;
                    text-decoration: none;
                    transition: color 0.2s;
                    font-size: 200%;
                }}

                .breadcrumb-item:hover {{
                    color: #26cc0e;
                    font-weight: bold;
                }}

                .item-container {{
                    display: flex;
                    align-items: center;
                }}

                .index-number {{
                    min-width: 3.5em;
                    text-align: right;
                    margin-right: 1em;
                    color: #666;
                }}

                table {{
                    border-collapse: collapse;
                    width: 100%;
                    background-color: white;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                    border-radius: 4px;
                }}

                th, td {{
                    padding: 12px 15px;
                    text-align: left;
                    border-bottom: 1px solid #eee;
                }}

                th {{
                    background-color: #f8f9fa;
                    font-weight: bold;
                    color: #495057;
                }}

                tr:hover {{
                    background-color: #f8f9fa;
                }}

                a {{
                    text-decoration: none;
                }}

                .folder {{
                    background-color: transparent ;
                    color: #1d910d;
                    font-weight: bold;
                    font-size: 120%;
                    padding: 3px 8px;
                    border-radius: 4px;
                    transition: background-color 0.2s;
                }}

                .folder:hover {{
                    background-color: transparent ;
                }}

                .file {{
                    color: #db0bee ;
                    background-color: transparent ;
                    padding: 3px 8px;
                    border-radius: 4px;
                    transition: background-color 0.2s;
                }}

                .file:hover {{
                    background-color: transparent ;
                }}

                .size-col {{
                    font-family: 'Source Code Pro', monospace;
                    text-align: right;
                }}

                h2 {{
                    color: #343a40;
                    margin-bottom: 20px;
                }}

                tr:last-child td {{
                    border-bottom: none;
                }}
            </style>
        </head>
        <body>
            <div class="breadcrumb">
                {breadcrumb}
            </div>
            <table>
                <thead>
                    <tr>
                        <th>Name</th>
                        <th style="text-align: right">Size</th>
                        <th>Modified</th>
                    </tr>
                </thead>
                <tbody>
                    {''.join(table_rows)}
                </tbody>
            </table>
        </body>
        </html>
        """
        return HTMLResponse(content=html_content)

    elif os.path.isfile(full_path):
        # Handle files
        ext = os.path.splitext(full_path)[1].lower()
        if ext in LEXER_MAPPING or full_path.endswith(".ipynb"):
            if full_path.endswith(".ipynb"):
                return await notebooks(full_path, credentials)
            else:
                return await render_file_with_pygments(full_path, ext, credentials)
        else:
            # Serve the file
            return FileResponse(full_path)

    else:
        raise HTTPException(status_code=404, detail="Path not found")


async def render_file_with_pygments(
    full_path: str, ext: str, credentials: HTTPBasicCredentials
):
    if not os.path.isfile(full_path):
        raise HTTPException(status_code=404, detail="File not found")
    try:
        with open(full_path, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        with open(full_path, "r", encoding="latin-1") as f:
            content = f.read()

    lexer_name = LEXER_MAPPING.get(ext, None)
    try:
        if lexer_name:
            lexer = get_lexer_by_name(lexer_name)
        else:
            lexer = guess_lexer_for_filename(full_path, content)
    except ClassNotFound:
        # Fallback to TextLexer if no lexer is found
        lexer = TextLexer()

    style_name = "manni"  # As in original CODE_16
    style = get_style_by_name(style_name)
    formatter = HtmlFormatter(linenos=True, style=style)
    highlighted_code = highlight(content, lexer, formatter)
    custom_css = """html *, pre { font-family: 'Source Code Pro', monospace !important; }
                   .linenodiv { color: #bbb !important; }"""
    html_content = f"""
    <html>
    <head>
        <title>{html.escape(os.path.basename(full_path))}</title>
        <link rel="icon" type="image/x-icon" href="/static/favicon.ico">
        <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap" rel="stylesheet">
        <style>{formatter.get_style_defs()}</style>
        <style>{custom_css}</style>
    </head>
    <body style="background-color: {style.background_color};">
        {highlighted_code}
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)


async def notebooks(full_path: str, credentials: HTTPBasicCredentials):
    if not os.path.isfile(full_path):
        raise HTTPException(status_code=404, detail="File not found")
    if full_path.endswith(".ipynb"):
        with open(full_path, "r", encoding="utf-8") as f:
            notebook_content = nbformat.read(f, as_version=4)
            html_exporter = nbconvert.HTMLExporter()
            (body, resources) = html_exporter.from_notebook_node(notebook_content)
            custom_css = 'html *, pre { font-family: "Source Code Pro", monospace  !important ; }'
            html_content = f"""
            <html>
            <head>
                <title>{html.escape(os.path.basename(full_path))}</title>
                <link rel="icon" type="image/x-icon" href="/static/favicon.ico">
                <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap" rel="stylesheet">
                <style>{custom_css}</style>
            </head>
            <body>
                {body}
            </body>
            </html>
            """
            return HTMLResponse(content=html_content)
    else:
        raise HTTPException(status_code=404, detail="File not found")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=16)
