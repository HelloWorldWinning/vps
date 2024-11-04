from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.responses import FileResponse, HTMLResponse
import os
from urllib.parse import quote, unquote
import secrets
from datetime import datetime
from typing import List

app = FastAPI()
security = HTTPBasic()

def format_size(size_in_bytes: int) -> str:
    """Convert size in bytes to human readable format."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_in_bytes < 1024.0:
            return f"{size_in_bytes:.1f} {unit}"
        size_in_bytes /= 1024.0
    return f"{size_in_bytes:.1f} PB"

def get_file_info(path: str) -> dict:
    """Get file/directory information including size and modification time."""
    stats = os.stat(path)
    return {
        'size': stats.st_size,
        'modified': datetime.fromtimestamp(stats.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
    }

def create_breadcrumb(path: str) -> str:
    """Create HTML breadcrumb navigation from path."""
    if path == '/':
        return '<a href="/" class="breadcrumb-item">/</a>'

    parts = path.split('/')
    breadcrumb_parts = []
    current_path = ''

    # Add root
    breadcrumb_parts.append('<a href="/" class="breadcrumb-item">/</a>')

    # Add each directory
    for part in parts:
        if part:  # Skip empty parts
            current_path = os.path.join(current_path, part)
            encoded_path = quote(current_path.lstrip('/'))
            breadcrumb_parts.append(
                f'<a href="/{encoded_path}" class="breadcrumb-item">{part}</a>/'
            )

    return ''.join(breadcrumb_parts)

def authenticate(credentials: HTTPBasicCredentials = Depends(security)):
    correct_username = "a"
    correct_password = "a"

    is_correct_username = secrets.compare_digest(credentials.username.encode('utf8'),
                                               correct_username.encode('utf8'))
    is_correct_password = secrets.compare_digest(credentials.password.encode('utf8'),
                                               correct_password.encode('utf8'))

    if not (is_correct_username and is_correct_password):
        raise HTTPException(
            status_code=401,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials

@app.get("/{path:path}")
async def read_path(path: str, credentials: HTTPBasicCredentials = Depends(authenticate)):
    # Decode URL-encoded path
    path = unquote(path)

    # Safely construct the full path
    full_path = os.path.normpath(os.path.join('/', path))
    if not full_path.startswith('/'):
        # Prevent path traversal attacks
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
        table_rows: List[str] = []

        # Add parent directory link if not in root
        if full_path != '/':
            parent_full_path = os.path.dirname(full_path)
            parent_rel_path = os.path.relpath(parent_full_path, '/')
            parent_url = quote(parent_rel_path)
            parent_info = get_file_info(parent_full_path)
            table_rows.append(f'''
                <tr>
                    <td>
                        <div class="item-container">
                            <span class="index-number">-</span>
                            <a href="/{parent_url}" class="folder">../</a>
                        </div>
                    </td>
                    <td class="size-col">-</td>
                    <td>{parent_info['modified']}</td>
                </tr>
            ''')

        # Add all directory contents
        for idx, item in enumerate(items, 1):
            item_full_path = os.path.join(full_path, item)
            item_rel_path = os.path.relpath(item_full_path, '/')
            item_url = quote(item_rel_path)
            item_info = get_file_info(item_full_path)

            if os.path.isdir(item_full_path):
                item_display = f"{item}/"
                item_size = "-"
                item_class = "folder"
            else:
                item_display = item
                item_size = format_size(item_info['size'])
                item_class = "file"

            table_rows.append(f'''
                <tr>
                    <td>
                        <div class="item-container">
                            <span class="index-number">{idx}.</span>
                            <a href="/{item_url}" class="{item_class}">{item_display}</a>
                        </div>
                    </td>
                    <td class="size-col">{item_size}</td>
                    <td>{item_info['modified']}</td>
                </tr>
            ''')

        # Create HTML content with table and custom styling
        html_content = f"""
        <html>
        <head>
            <meta charset="UTF-8">
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
                    background-color: #ffffff;
                    color: #1d910d;
                    font-weight: bold;
                    font-size: 120%;
                    padding: 3px 8px;
                    border-radius: 4px;
                    transition: background-color 0.2s;
                }}

                .folder:hover {{
                    background-color: #f8f9fa;
                }}

                .file {{
                    color: #ffffff;
                    background-color: #b33105;
                    padding: 3px 8px;
                    border-radius: 4px;
                    transition: background-color 0.2s;
                }}

                .file:hover {{
                    background-color: #8b2604;
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
        # Serve the file
        return FileResponse(full_path)
    else:
        raise HTTPException(status_code=404, detail="Path not found")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7788, reload=True)
