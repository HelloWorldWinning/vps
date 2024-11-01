from flask import Flask, request, render_template_string
import requests
import json

app = Flask(__name__)

HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Token Counter</title>
    <style>
        body { font-family: Arial, sans-serif; background-color: #f0f0f0; margin: 0; padding: 0; }
        .container { width: 90%; max-width: 1200px; margin: 20px auto; display: flex; }
        .left-col, .right-col { width: 50%; padding: 20px; box-sizing: border-box; }
        .counter { background-color: #ffffff; border-radius: 10px; padding: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); text-align: center; margin-bottom: 20px; }
        .counter-label { font-size: 1.2em; color: #333; margin-bottom: 10px; }
        .response-count { font-size: 5em; font-weight: bold; color: #2c3e50; display: block; }
        .input-container { background-color: #ffffff; border-radius: 10px; padding: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        textarea { width: 100%; font-size: 1.2em; padding: 0px; border: 1px solid #ddd; border-radius: 5px; resize: vertical; }
        h2 { margin-top: 0; }
    </style>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script>
        $(document).ready(function() {
            $('#inputText').on('input', function() {
                var inputText = $(this).val();
                $.ajax({
                    url: '/count_tokens',
                    method: 'POST',
                    data: { inputText: inputText },
                    success: function(response) {
                        var counts = JSON.parse(response);
                        $('.response-count-new').text(counts.new.toLocaleString());
                        $('.response-count-old').text(counts.old.toLocaleString());
                    }
                });
            });
        });
    </script>
</head>
<body>
    <div class="container">
        <div class="left-col">
            <div class="counter">
                <div class="counter-label">GPT-4o</div>
                <span class="response-count response-count-new">0</span>
            </div>
            <div class="counter">
                <div class="counter-label">GPT-4</div>
                <span class="response-count response-count-old">0</span>
            </div>
        </div>
        <div class="right-col">
            <div class="input-container">
                <h2>Token Counter</h2>
                <textarea id="inputText" name="inputText" rows="10" placeholder="Enter your text here..."></textarea>
            </div>
        </div>
    </div>
</body>
</html>'''

@app.route('/', methods=['GET'])
def home():
    return render_template_string(HTML_TEMPLATE)

@app.route('/count_tokens', methods=['POST'])
def count_tokens():
    input_text = request.form['inputText']
    new_count = call_token_api(input_text, 'tokenize_o')
    old_count = call_token_api(input_text, 'tokenize')
    return json.dumps({'new': new_count, 'old': old_count})

def call_token_api(input_text, endpoint):
    API_URL = f"http://127.0.0.1:6969/{endpoint}"
    headers = {'Content-Type': 'application/json'}
    data = {"input_string": input_text}
    try:
        response = requests.post(API_URL, headers=headers, json=data)
        if response.status_code == 200:
            return int(response.text.replace(',', ''))
        else:
            return "Error: Failed to retrieve token count."
    except requests.exceptions.RequestException as e:
        return "Request Exception: Something went wrong with the request."
    except ValueError:
        return "Error: Unexpected response format from the API."

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=6868)
