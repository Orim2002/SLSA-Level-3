from flask import Flask, jsonify, request

app = Flask(__name__)


@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy"}), 200

@app.route('/')
def home():
    return """
        <h1>Welcome to my Simple Flask App!</h1>
        <p>Ori Maor SLSA Level 3 sample app.</p>
        <nav>
            <a href="/about">About</a>
        </nav>
    """

@app.route('/about')
def about():
    return """
        <h1>About This Project</h1>
        <p>It's simple, but it gets the job done.</p>
        <a href="/">Go Back Home</a>
    """

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)