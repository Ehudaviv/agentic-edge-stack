import json
import time
from locust import HttpUser, task, between, events

class FastAPIStreamUser(HttpUser):
    """
    Simulates concurrent users hitting the FastAPI AI Agent streaming endpoint (/chat).
    """
    # Think time between requests (simulate human query typing)
    wait_time = between(1, 4)

    @task
    def test_streaming_chat(self):
        headers = {
            "Content-Type": "application/json"
        }
        # Standard query to trigger both Qdrant tool search and Ollama inference
        payload = {
            "message": "What is the Agentic Edge Stack? Explain briefly."
        }
        
        start_time = time.time()
        first_token_time = None
        total_bytes = 0
        
        # Send POST request with stream=True to process SSE token-by-token
        with self.client.post("/chat", json=payload, headers=headers, stream=True, catch_response=True) as response:
            if response.status_code != 200:
                response.failure(f"HTTP status code: {response.status_code}")
                return
            
            try:
                # Read chunks line by line
                for line in response.iter_lines():
                    if line:
                        total_bytes += len(line)
                        decoded_line = line.decode('utf-8').strip()
                        
                        if decoded_line.startswith("data:"):
                            # Capture Time-to-First-Token (TTFT) when first data chunk arrives
                            if first_token_time is None:
                                first_token_time = time.time() - start_time
                                # Record TTFT as a custom metric in Locust (in milliseconds)
                                self.environment.events.request.fire(
                                    request_type="SSE_TTFT",
                                    name="/chat [TTFT]",
                                    response_time=first_token_time * 1000,
                                    response_length=0,
                                    exception=None,
                                    context=response.request_meta.get("context", {})
                                )
                            
                            # Extract JSON string payload
                            data_str = decoded_line[5:].strip()
                            if data_str == "[DONE]":
                                break
                            
                            # Verify if there is an error in the stream content
                            try:
                                data_json = json.loads(data_str)
                                if "error" in data_json:
                                    response.failure(f"Error returned in stream JSON: {data_json['error']}")
                                    return
                            except json.JSONDecodeError:
                                pass
                
                # Record the overall streaming execution time
                total_duration = time.time() - start_time
                self.environment.events.request.fire(
                    request_type="SSE_Total",
                    name="/chat [Total Stream]",
                    response_time=total_duration * 1000,
                    response_length=total_bytes,
                    exception=None,
                    context=response.request_meta.get("context", {})
                )
                
                response.success()
                
            except Exception as e:
                response.failure(f"Exception encountered during stream iteration: {str(e)}")
