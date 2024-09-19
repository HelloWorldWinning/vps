from flask import Flask, request, render_template_string
import requests

app = Flask(__name__)

# HTML Template for the input form and to display the result, with added CSS for styling
HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Token Counter</title>
    <style>
        body { font-family: Arial, sans-serif; }
        .container { width: 50%; margin: auto; }
        textarea { width: 100%; font-size: 1.2em; }
        input[type=submit] { font-size: 1.2em; }
        .response { font-size: 1.5em; font-weight: bold; color: #333; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Token Counter</h2>
        <form method="POST">
            <label for="inputText">Enter text:</label><br>
            <textarea id="inputText" name="inputText" rows="10" cols="50"></textarea><br><br>
            <input type="submit" value="Count Tokens">
        </form>
        {% if response %}
            <div class="response">Token count: <span>{{ response }}</span></div>
        {% endif %}
    </div>
</body>
</html>'''

@app.route('/', methods=['GET', 'POST'])
def count_tokens():
    if request.method == 'POST':
        input_text = request.form['inputText']
        response = call_token_api(input_text)
        return render_template_string(HTML_TEMPLATE, response=response)
    return render_template_string(HTML_TEMPLATE, response=None)

def call_token_api(input_text):
    API_URL = "http://s.jingyi.today:6969/tokenize"
    headers = {'Content-Type': 'application/json'}
    data = {"input_string": input_text}
    
    try:
        response = requests.post(API_URL, headers=headers, json=data)
        if response.status_code == 200:
            return response.text
        else:
            return "Error: Failed to retrieve token count."
    except requests.exceptions.RequestException as e:
        return "Request Exception: Something went wrong with the request."

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=6868)
