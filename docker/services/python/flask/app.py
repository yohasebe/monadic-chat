from flask import Flask, request, jsonify
import importlib
import pkgutil
from tiktoken.registry import get_encoding

app = Flask(__name__)
app.config['JSON_AS_ASCII'] = False
app.config['JSONIFY_MIMETYPE'] = 'application/json;charset=utf-8'

default_model = 'gpt-3.5-turbo'

# Function to dynamically load model_to_encoding_map from tiktoken/model.py
def load_model_to_encoding_map():
    # Find the path to the tiktoken package
    tiktoken_path = pkgutil.get_loader("tiktoken").get_filename()
    model_path = tiktoken_path.replace("__init__.py", "model.py")

    # Import model_to_encoding_map from model.py
    spec = importlib.util.spec_from_file_location("tiktoken.model", model_path)
    tiktoken_model = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tiktoken_model)

    return tiktoken_model.MODEL_TO_ENCODING

# Load model_to_encoding_map
model_to_encoding_map = load_model_to_encoding_map()

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for service availability verification"""
    return jsonify({'status': 'ok', 'service': 'python-flask'})

@app.route('/get_encoding_name', methods=['POST'])
def get_encoding_name():
    data = request.json
    model_name = data.get('model_name', default_model)
    if model_name in model_to_encoding_map:
        return jsonify({'encoding_name': model_to_encoding_map[model_name]})
    else:
        return jsonify({'error': 'Model not found'})

@app.route('/count_tokens', methods=['POST'])
def count_tokens():
    data = request.json
    text = data.get('text', '')
    model_name = data.get('model_name', default_model)
    encoding_name = data.get('encoding_name', "o200k_base")

    # if encoding_name is not provided, get the encoding name from the model name
    if encoding_name == "":
        encoding_name = model_to_encoding_map[model_name]

    encoding = get_encoding(encoding_name)
    tokens = encoding.encode(text)
    return jsonify({'number_of_tokens': len(tokens)})

@app.route('/get_tokens_sequence', methods=['POST'])
def get_tokens_sequence():
    data = request.json
    text = data.get('text', '')
    model_name = data.get('model_name', default_model)
    encoding_name = model_to_encoding_map[model_name]
    encoding = get_encoding(encoding_name)
    tokens = encoding.encode(text)  # Using encode instead of encode_ordinary
    return jsonify({'tokens_sequence': ",".join(map(str, tokens))})

@app.route('/decode_tokens', methods=['POST'])
def decode_tokens():
    data = request.json
    tokens_str = data.get('tokens', '')
    model_name = data.get('model_name', 'gpt-3.5-turbo')
    encoding_name = model_to_encoding_map[model_name]
    tokens = list(map(int, tokens_str.replace(",", " ").split()))
    encoding = get_encoding(encoding_name)
    try:
        original_text = encoding.decode(tokens)
    except Exception as e:
        return jsonify({'error': str(e)})
    return jsonify({'original_text': original_text})

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')

