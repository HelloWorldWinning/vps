from flask import Flask, request

app = Flask(__name__)

API_URL = "http://s.jingyi.today:6969/tokenize"

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        input_text = request.form['input_text']
        data = {'input_string': input_text}
        response = requests.post(API_URL, json=data)
        result = response.json()
        token_count = result['token_count']
        return f'''
            <!DOCTYPE html>
            <html>
            <head>
                <title>Token Count Result</title>
            </head>
            <body>
                <h1>Token Count Result</h1>
                <p>Input Text:</p>
                <pre>{input_text}</pre>
                <p>Token Count: {token_count}</p>
                <a href="/">Count Again</a>
            </body>
            </html>
        '''
    return '''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Token Counter</title>
        </head>
        <body>
            <h1>Token Counter</h1>
            <form method="POST">
                <textarea name="input_text" rows="5" cols="50"></textarea><br>
                <input type="submit" value="Count Tokens">
            </form>
        </body>
        </html>
    '''

if __name__ == '__main__':
    app.run(debug=True,host="0.0.0.0",port=6868)

