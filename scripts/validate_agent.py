#!/usr/bin/env python3
import time
import subprocess
import threading
import sys
import json
import httpx
from http.server import HTTPServer, BaseHTTPRequestHandler

# Setup simple HTTP mock server for Ollama API
class MockOllamaHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress logging of HTTP requests to keep output clean
        return

    def do_POST(self):
        if self.path == "/api/chat":
            content_length = int(self.headers['Content-Length'])
            post_data = json.loads(self.rfile.read(content_length))
            
            # Read messages to check if a tool was returned previously
            messages = post_data.get("messages", [])
            stream = post_data.get("stream", False)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json' if not stream else 'application/x-ndjson')
            self.end_headers()

            # Check if this is the initial call (asking for tools)
            # Or if it's the second call (submitting tool results)
            has_tool_result = any(msg.get("role") == "tool" for msg in messages)
            
            if not has_tool_result and not stream:
                # Decide to call query_vector_store
                response = {
                    "model": "qwen2.5:0.5b",
                    "created_at": "2026-06-08T00:00:00Z",
                    "message": {
                        "role": "assistant",
                        "content": "",
                        "tool_calls": [
                            {
                                "function": {
                                    "name": "query_vector_store",
                                    "arguments": {"query": "Agentic Edge Stack"}
                                }
                            }
                        ]
                    },
                    "done": True
                }
                self.wfile.write(json.dumps(response).encode('utf-8'))
            else:
                # This is the streaming final response
                tokens = ["The ", "Agentic ", "Edge ", "Stack ", "is ", "running ", "perfectly ", "with ", "mocked ", "dependencies!"]
                
                if stream:
                    for token in tokens:
                        chunk = {
                            "model": "qwen2.5:0.5b",
                            "created_at": "2026-06-08T00:00:00Z",
                            "message": {
                                "role": "assistant",
                                "content": token
                            },
                            "done": False
                        }
                        self.wfile.write((json.dumps(chunk) + "\n").encode('utf-8'))
                        time.sleep(0.05)
                    
                    # End chunk
                    end_chunk = {
                        "model": "qwen2.5:0.5b",
                        "created_at": "2026-06-08T00:00:00Z",
                        "message": {"role": "assistant", "content": ""},
                        "done": True
                    }
                    self.wfile.write((json.dumps(end_chunk) + "\n").encode('utf-8'))
                else:
                    response = {
                        "model": "qwen2.5:0.5b",
                        "created_at": "2026-06-08T00:00:00Z",
                        "message": {
                            "role": "assistant",
                            "content": "".join(tokens)
                        },
                        "done": True
                    }
                    self.wfile.write(json.dumps(response).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

def run_mock_ollama(port):
    server = HTTPServer(('localhost', port), MockOllamaHandler)
    server.serve_forever()

def main():
    print("=========================================================")
    print("Starting FastAPI Agent Service Local Validation")
    print("=========================================================")

    # 1. Start mock Ollama server on port 18434
    mock_port = 18434
    print(f"1. Launching mock Ollama server on localhost:{mock_port}...")
    ollama_thread = threading.Thread(target=run_mock_ollama, args=(mock_port,), daemon=True)
    ollama_thread.start()
    time.sleep(1)

    # 2. Start FastAPI application using uvicorn as a subprocess
    print("2. Launching FastAPI Agent application...")
    env = {
        **subprocess.os.environ,
        "LLM_URL": f"http://localhost:{mock_port}",
        "QDRANT_URL": "http://localhost:16333",  # offline URL to trigger mock fallback
        "PYTHONPATH": "src"
    }
    
    # Run uvicorn on localhost:8080
    app_process = subprocess.Popen(
        ["uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8080", "--log-level", "warning"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    # Wait for FastAPI to start up
    time.sleep(2)

    try:
        # 3. Query /health
        print("3. Querying /health endpoint...")
        health_res = httpx.get("http://localhost:8080/health")
        print(f"Health Response: {health_res.json()}")

        # 4. Query /metrics (Track B check)
        print("4. Querying Prometheus /metrics endpoint...")
        metrics_res = httpx.get("http://localhost:8080/metrics")
        print(f"Metrics response contains HTTP request count: {'http_requests_total' in metrics_res.text}")

        # 5. Query streaming /chat endpoint
        print("5. Triggering streaming /chat request for 'Tell me about Agentic Edge Stack'...")
        
        with httpx.stream("POST", "http://localhost:8080/chat", json={"message": "Tell me about Agentic Edge Stack"}) as r:
            if r.status_code != 200:
                print(f"Error: Chat response failed with status {r.status_code}")
                sys.exit(1)
                
            print("\n--- Streaming Response Start ---")
            for line in r.iter_lines():
                if line.startswith("data: "):
                    data_str = line[6:]
                    if data_str == "[DONE]":
                        print("\n--- Streaming Response End ---")
                        break
                    
                    try:
                        data = json.loads(data_str)
                        if "token" in data:
                            print(data["token"], end="", flush=True)
                        elif "error" in data:
                            print(f"\n[Stream Error] {data['error']}")
                    except Exception as e:
                        print(f"\nFailed to parse line: {line}. Error: {e}")
            print()

        print("=========================================================")
        print("Validation Successful: Streaming SSE and mock integration passed!")
        print("=========================================================")
        sys.exit(0)

    except Exception as e:
        print(f"\nValidation failed with error: {e}")
        sys.exit(1)
    finally:
        # Cleanup
        print("Cleaning up background processes...")
        app_process.terminate()
        app_process.wait()

if __name__ == "__main__":
    main()
