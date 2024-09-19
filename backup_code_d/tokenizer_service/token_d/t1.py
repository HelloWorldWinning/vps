from flask import Flask, request, render_template_string
import requests

app = Flask(__name__)

# HTML Template for the input form and to display the result
HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Token Counter</title>
</head>
<body>
    <h2>Token Counter</h2>
    <form method="POST">
        <label for="inputText">Enter text:</label><br>
        <textarea id="inputText" name="inputText" rows="4" cols="50"></textarea><br><br>
        <input type="submit" value="Count Tokens">
    </form>
    {% if response %}
        <h3>Response:</h3>
        <pre>{{ response }}</pre>
    {% endif %}
</body>
</html>'''

@app.route('/', methods=['GET', 'POST'])
def count_tokens():
    if request.method == 'POST':
        input_text = request.form['inputText']
        response = call_token_api(input_text)
        # Assuming the response content is just the count, directly display it.
        # The response is not being validated or parsed as JSON.
        return render_template_string(HTML_TEMPLATE, response=response)
    return render_template_string(HTML_TEMPLATE, response=None)

def call_token_api(input_text):
    API_URL = "http://s.jingyi.today:6969/tokenize"
    headers = {'Content-Type': 'application/json'}
    data = {"input_string": input_text}
    
    try:
        response = requests.post(API_URL, headers=headers, json=data)
        if response.status_code == 200:
            # Directly return the text component of the response
            return response.text
        else:
            return "Error: Failed to retrieve token count."
    except requests.exceptions.RequestException as e:
        return "Request Exception: Something went wrong with the request."

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=6868)
