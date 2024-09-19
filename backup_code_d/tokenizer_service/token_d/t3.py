from flask import Flask, request, render_template_string
import requests

app = Flask(__name__)

# HTML Template for the input form and to display the result, with added CSS for styling
HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=2.0"> <!-- Here we set the initial scale to 2.0 to make everything bigger -->
    <title>Token Counter</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            background: #f4f4f4;
            color: #333;
            line-height: 1.6;
        }
        .container {
            max-width: 800px; /* A larger fixed width for larger screen */
            margin: 30px auto;
            padding: 20px;
            background: #fff;
            box-shadow: 0 5px 10px rgba(0, 0, 0, 0.1);
        }
        h2 {
            font-size: 3em; /* Make the heading larger */
            margin-bottom: 10px;
        }
        textarea {
            width: 100%;
            height: 150px;
            font-size: 1.5em; /* Make the font larger */
            margin-bottom: 20px;
            padding: 10px;
            box-sizing: border-box;
        }
        input[type=submit] {
            font-size: 1.5em; /* Make the submit button larger */
            padding: 10px 20px;
        }
        .response {
            font-size: 2em; /* Make the response size larger */
            font-weight: bold;
            color: #e74c3c; /* Bright red color for attention */
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h2>Token Counter</h2>
        <form method="POST">
            <label for="inputText">Enter text:</label><br>
            <textarea id="inputText" name="inputText" rows="4" cols="50"></textarea><br><br>
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
