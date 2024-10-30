from flask import Flask, request, render_template_string
import requests

app = Flask(__name__)

# HTML template for the webpage
template = '''
<!doctype html>
<html>
<head>
    <title>Text Extractor</title>
</head>
<body>
    <h1>URL Text Extractor</h1>
    <form method="post">
        <label for="url">Enter URL:</label>
        <input type="text" name="url" id="url" size="80" required>
        <input type="submit" value="Extract Text">
    </form>
    {% if text %}
        <h2>Extracted Text:</h2>
        <pre>{{ text }}</pre>
    {% endif %}
    {% if error %}
        <h2>Error:</h2>
        <p>{{ error }}</p>
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
  #  app.run(debug=True)
    app.run(host='0.0.0.0', port=9977, debug=False)

