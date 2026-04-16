from flask import Flask, request
import os

app = Flask(__name__)

def get_injection():
    if request.form["username"] == "alert('hello!')":
        print("XSS attack detected!")
        os._exit(1)
    return request.form["username"]
   
@app.route('/welcome', methods=['POST'])
def welcome():
    return "ようこそ、" + get_injection() + "さん"

@app.route('/')
def index():
    return """
    <form action="/welcome" method="POST">
        <input type="text" name="username" placeholder="Your name"><br />
        <input type="submit" value="login">
    </form>
    """

app.run(port=5000, debug=True)