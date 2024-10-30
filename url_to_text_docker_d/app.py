from flask import Flask, request, render_template_string
import requests

app = Flask(__name__)

# HTML template for the webpage
template = '''
<!doctype html>
<html>
<head>
    <title>Text Extractor</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
        }
        #text-output {
            white-space: pre-wrap;
            word-wrap: break-word;
            padding: 15px;
            border: 1px solid #ccc;
            max-width: 100%;
            box-sizing: border-box;
            background-color: #f9f9f9;
        }
        #url-input {
            width: 80%;
            padding: 8px;
            font-size: 16px;
            margin-bottom: 20px;
        }
        #submit-btn {
            display: none; /* Hide the submit button */
        }
        h1, h2 {
            color: #333;
        }
        form {
            margin-bottom: 30px;
        }
    </style>
    <script>
        // Submit the form when the URL input loses focus or when Enter key is pressed
        function submitForm(event) {
            if (event.type === 'change' || (event.type === 'keydown' && event.keyCode === 13)) {
                event.preventDefault(); // Prevent default action
                document.getElementById('url-form').submit();
            }
        }
    </script>
</head>
<body>
    <h1>URL Text Extractor</h1>
    <form method="post" id="url-form">
        <label for="url-input">Enter URL:</label><br>
        <input type="text" name="url" id="url-input" required
               onchange="submitForm(event)"
               onkeydown="submitForm(event)">
        <input type="submit" id="submit-btn">
    </form>
    {% if text %}
        <h2>Extracted Text:</h2>
        <div id="text-output">{{ text }}</div>
    {% endif %}
    {% if error %}
        <h2>Error:</h2>
        <div id="text-output">{{ error }}</div>
    {% endif %}
</body>
</html>
'''

@app.route('/', methods=['GET', 'POST'])
def index():
    text = None
    error = None
    if request.method == 'POST':
        url = request.form.get('url')
        if url:
            # Backend API endpoint
            api_url = 'http://127.0.0.1:9966/url'
            #api_url = 'http://jp.zhulei.eu.org:9966/url'
            headers = {
                'Authorization': 'Bearer _to_know_world'
            }
            params = {
                'url': url
            }
            try:
                # Send GET request to the backend API
                response = requests.get(api_url, headers=headers, params=params)
                response.raise_for_status()  # Raise an error for bad status codes
                data = response.json()
                text = data.get('text', 'No text found.')
            except requests.exceptions.RequestException as e:
                error = f'An error occurred: {e}'
            except ValueError:
                error = 'Invalid response from the backend API.'
    return render_template_string(template, text=text, error=error)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9977, debug=False)

