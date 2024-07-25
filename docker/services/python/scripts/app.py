from flask import Flask, request, jsonify
import importlib
import pkgutil
from tiktoken.registry import get_encoding
from functools import lru_cache

app = Flask(__name__)

# Function to dynamically load model_to_encoding_map from tiktoken/model.py
def load_model_to_encoding_map():
    tiktoken_path = pkgutil.get_loader("tiktoken").get_filename()
    model_path = tiktoken_path.replace("__init__.py", "model.py")
    spec = importlib.util.spec_from_file_location("tiktoken.model", model_path)
    tiktoken_model = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tiktoken_model)
    return tiktoken_model.MODEL_TO_ENCODING

# Load model_to_encoding_map at startup
model_to_encoding_map = load_model_to_encoding_map()

@lru_cache(maxsize=None)
def get_encoding_name(model_name):
    if model_name in model_to_encoding_map:
        return model_to_encoding_map[model_name]
    else:
        raise ValueError(f"Model name '{model_name}' is not recognized.")

@lru_cache(maxsize=None)
def get_cached_encoding(encoding_name):
    return get_encoding(encoding_name)

@app.route('/count_tokens', methods=['POST'])
def count_tokens():
    data = request.json
    text = data.get('text', '')
    model_name = data.get('model_name', 'gpt-3.5-turbo')
    encoding_name = get_encoding_name(model_name)
    encoding = get_cached_encoding(encoding_name)
    tokens = encoding.encode_ordinary(text)
    return jsonify({'number_of_tokens': len(tokens)})

@app.route('/get_tokens_sequence', methods=['POST'])
def get_tokens_sequence():
    data = request.json
    text = data.get('text', '')
    model_name = data.get('model_name', 'gpt-3.5-turbo')
    encoding_name = get_encoding_name(model_name)
    encoding = get_cached_encoding(encoding_name)
    tokens = encoding.encode_ordinary(text)
    return jsonify({'tokens_sequence': ",".join(map(str, tokens))})

@app.route('/decode_tokens', methods=['POST'])
def decode_tokens():
    data = request.json
    tokens_str = data.get('tokens', '')
    model_name = data.get('model_name', 'gpt-3.5-turbo')
    encoding_name = get_encoding_name(model_name)
    tokens = list(map(int, tokens_str.replace(",", " ").split()))
    encoding = get_cached_encoding(encoding_name)
    original_text = encoding.decode(tokens)
    return jsonify({'original_text': original_text})

if __name__ == '__main__':
    app.run(debug=False, host='0.0.0.0')

