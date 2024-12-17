from fastapi import FastAPI, Request, Form, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
import httpx
import uvicorn

app = FastAPI()

# Create templates directory
templates = Jinja2Templates(directory="templates")

# HTML templates as strings (in real app, these would be separate files)
HOME_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Web Content Extractor</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap');

        body {
            margin: 0;
            font-family: 'Inter', sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            background: linear-gradient(135deg, #f5f7fa 0%, #e4e9f2 100%);
        }

        .container {
            width: 90%;
            max-width: 600px;
            text-align: center;
            padding: 2rem;
            background: white;
            border-radius: 16px;
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.05);
        }

        h1 {
            color: #1a1f36;
            font-size: 2rem;
            font-weight: 600;
            margin-bottom: 0.5rem;
        }

        .description {
            color: #4f566b;
            font-size: 1.1rem;
            margin-bottom: 2rem;
            line-height: 1.5;
        }

        form {
            width: 100%;
            position: relative;
        }

        .input-container {
            position: relative;
            margin-top: 1rem;
        }

        input[type="text"] {
            width: 100%;
            padding: 1rem 1.2rem;
            font-size: 1rem;
            border: 2px solid #e4e9f2;
            border-radius: 12px;
            transition: all 0.3s ease;
            box-sizing: border-box;
            font-family: 'Inter', sans-serif;
            background: #f8fafc;
        }

        input[type="text"]:focus {
            outline: none;
            border-color: #5850ec;
            background: white;
            box-shadow: 0 0 0 3px rgba(88, 80, 236, 0.1);
        }

        input[type="text"]::placeholder {
            color: #a0aec0;
        }

        input[type="submit"] {
            display: none;
        }

        .examples {
            margin-top: 2rem;
            font-size: 0.9rem;
            color: #6b7280;
        }
    </style>
    <script>
        function submitForm() {
            const form = document.getElementById('url-form');
            const input = document.querySelector('input[type="text"]');
            if (input.value.trim() !== '') {
                form.submit();
            }
        }

        document.addEventListener('DOMContentLoaded', function() {
            const input = document.querySelector('input[type="text"]');
            let typingTimer;
            const doneTypingInterval = 800; // ms

            input.addEventListener('input', function() {
                clearTimeout(typingTimer);
                if (this.value) {
                    typingTimer = setTimeout(submitForm, doneTypingInterval);
                }
            });

            input.addEventListener('keydown', function(e) {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    submitForm();
                }
            });
        });
    </script>
</head>
<body>
    <div class="container">
        <h1>Extract Web Content</h1>
        <p class="description">Paste any webpage URL to extract its readable content, instantly cleaned and formatted.</p>
        <form method="post" id="url-form" action="/extract">
            <div class="input-container">
                <input type="text"
                       name="url"
                       required
                       placeholder="Paste a URL here..."
                       autocomplete="off"
                       spellcheck="false">
            </div>
        </form>
        <div class="examples">
            Works with articles, blog posts, news sites, and more
        </div>
    </div>
</body>
</html>
"""

RESULT_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Extracted Text</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap');

        body {
            margin: 0;
            padding: 20px;
            font-family: 'Source Code Pro', monospace;
            line-height: 1.6;
        }

        #text-content {
            white-space: pre-wrap;
            word-wrap: break-word;
            font-size: 18px;
        }
    </style>
</head>
<body>
    <div id="text-content">{{ text }}</div>
</body>
</html>
"""


@app.get("/", response_class=HTMLResponse)
async def home():
    return HOME_TEMPLATE


@app.post("/extract", response_class=HTMLResponse)
async def extract(url: str = Form(...)):
    try:
        # Backend API endpoint
        api_url = "http://127.0.0.1:9966/url"
        headers = {"Authorization": "Bearer _to_know_world"}
        params = {"url": url}

        async with httpx.AsyncClient() as client:
            response = await client.get(api_url, headers=headers, params=params)
            response.raise_for_status()
            data = response.json()
            text = data.get("text", "No text found.")

            # Return only the extracted text in the result template
            return RESULT_TEMPLATE.replace("{{ text }}", text)

    except httpx.RequestError as e:
        raise HTTPException(
            status_code=500, detail=f"Error accessing backend: {str(e)}"
        )
    except ValueError:
        raise HTTPException(status_code=500, detail="Invalid response from backend")


if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=9977, reload=False)
