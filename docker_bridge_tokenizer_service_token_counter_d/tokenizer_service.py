from flask import Flask, request
import tiktoken

app = Flask(__name__)


@app.route('/tokenize_o', methods=['POST'])
def tokenize_o():
    # Get input string from the request
    data = request.get_json()
    input_string = data.get('input_string', '')

    # Get the encoding for GPT-4
    encoding = tiktoken.encoding_for_model("gpt-4o")

    num_tokens = len(encoding.encode(input_string))

    # Return the number of tokens as a plain response
    num_tokens = f'{num_tokens:,}'

    return str(num_tokens)



@app.route('/tokenize', methods=['POST'])
def tokenize():
    # Get input string from the request
    data = request.get_json()
    input_string = data.get('input_string', '')

    # Get the encoding for GPT-4
    encoding = tiktoken.encoding_for_model("gpt-4")

    # Tokenize the string using GPT-4 encoding
    num_tokens = len(encoding.encode(input_string))

    # Return the number of tokens as a plain response
    num_tokens = f'{num_tokens:,}'

    return str(num_tokens)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=6969)

