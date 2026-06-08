import json
import logging
import httpx
from typing import AsyncGenerator, List, Dict, Any
from app.config import settings
from app.tools import query_vector_store

logger = logging.getLogger(__name__)

# Define the tool schema for Ollama's tool calling
VECTOR_STORE_TOOL = {
    "type": "function",
    "function": {
        "name": "query_vector_store",
        "description": "Query the vector database/knowledge base for facts about the Agentic Edge Stack, k3d, Kubernetes HPA, quantization, or ArgoCD.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The search term or topic to look up."
                }
            },
            "required": ["query"]
        }
    }
}

async def run_agent_stream(user_message: str) -> AsyncGenerator[str, None]:
    """
    Executes a native agent loop.
    1. Sends query to Ollama with tool definitions.
    2. If Ollama requests a tool call, executes it and sends results back.
    3. Streams the final output tokens.
    """
    messages = [
        {"role": "system", "content": "You are a helpful MLOps AI Assistant. You have access to a vector database lookup tool. Always try to query the vector database if the user asks about system components like Agentic Edge Stack, k3d, HPA, quantization, or ArgoCD to retrieve the most up-to-date and accurate information."},
        {"role": "user", "content": user_message}
    ]

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            logger.info("Sending initial request to Ollama to determine if a tool is needed...")
            
            # Step 1: Call Ollama with tools
            response = await client.post(
                f"{settings.llm_url}/api/chat",
                json={
                    "model": settings.llm_model,
                    "messages": messages,
                    "tools": [VECTOR_STORE_TOOL],
                    "stream": False
                }
            )
            
            if response.status_code != 200:
                logger.error(f"Ollama server returned error status: {response.status_code}")
                yield f"[Error] Inference server returned {response.status_code}. Make sure Ollama is running."
                return

            res_json = response.json()
            message = res_json.get("message", {})
            tool_calls = message.get("tool_calls", [])

            # Step 2: Handle tool calling if requested
            if tool_calls:
                # Add the assistant's message with tool calls to history
                messages.append(message)
                
                for tool_call in tool_calls:
                    func_name = tool_call.get("function", {}).get("name")
                    args = tool_call.get("function", {}).get("arguments", {})
                    
                    if isinstance(args, str):
                        try:
                            args = json.loads(args)
                        except Exception:
                            args = {}

                    logger.info(f"Ollama requested tool call: {func_name} with args {args}")
                    
                    if func_name == "query_vector_store":
                        query = args.get("query", user_message)
                        if isinstance(query, dict):
                            # Extract query if nested or falls back to user_message
                            if "query" in query and isinstance(query["query"], str):
                                query = query["query"]
                            else:
                                # If it looks like schema properties, fallback to user_message
                                is_schema_def = any(k in query for k in ["description", "type", "properties"])
                                if is_schema_def:
                                    query = user_message
                                else:
                                    candidates = [v for v in query.values() if isinstance(v, str) and v.lower() != "string"]
                                    query = candidates[0] if candidates else user_message
                        if not isinstance(query, str):
                            query = str(query)
                        
                        tool_result = query_vector_store(query)
                        logger.info(f"Tool executed. Result summary: {tool_result[:100]}...")
                        
                        # Add tool execution result to history
                        messages.append({
                            "role": "tool",
                            "name": func_name,
                            "content": tool_result
                        })
                    else:
                        logger.warning(f"Unknown tool requested: {func_name}")
                
                # Step 3: Stream the response with tool results included
                logger.info("Streaming response from Ollama after tool execution...")
                async for chunk in _stream_ollama(client, messages):
                    yield chunk
            else:
                # No tool call needed. Stream the content directly if it's there
                content = message.get("content", "")
                if content:
                    logger.info("Streaming direct answer from initial response...")
                    # Since we got it non-streaming, we can just yield it in chunks or run a quick stream.
                    # Yielding in chunks simulates the stream experience.
                    chunk_size = 4
                    for i in range(0, len(content), chunk_size):
                        yield content[i:i+chunk_size]
                else:
                    # In case of empty, double-check stream
                    async for chunk in _stream_ollama(client, messages):
                        yield chunk

    except httpx.ConnectError as ce:
        logger.error(f"Could not connect to Ollama at {settings.llm_url}: {ce}")
        yield "[Error] Could not connect to Ollama. Running in offline/mock mode? Please verify Ollama service status."
    except Exception as e:
        logger.exception("Error during agent execution loop:")
        yield f"[Error] An unexpected error occurred: {e}"

async def _stream_ollama(client: httpx.AsyncClient, messages: List[Dict[str, Any]]) -> AsyncGenerator[str, None]:
    """
    Helper to stream tokens from Ollama's chat API.
    """
    try:
        async with client.stream(
            "POST",
            f"{settings.llm_url}/api/chat",
            json={
                "model": settings.llm_model,
                "messages": messages,
                "stream": True
            },
            timeout=30.0
        ) as response:
            if response.status_code != 200:
                yield f"[Error] Ollama stream request failed with status: {response.status_code}"
                return

            async for line in response.aiter_lines():
                if not line:
                    continue
                try:
                    chunk_data = json.loads(line)
                    token = chunk_data.get("message", {}).get("content", "")
                    if token:
                        yield token
                except Exception as ex:
                    logger.warning(f"Error parsing SSE chunk: {ex}")
    except Exception as e:
        yield f"[Error] Stream connection interrupted: {e}"
