import logging
from typing import Any
from qdrant_client import QdrantClient
from qdrant_client.http import exceptions
from qdrant_client.models import Distance, VectorParams, PointStruct
from app.config import settings

logger = logging.getLogger(__name__)

# Initialize Qdrant client lazily or handle errors gracefully
_qdrant_client = None

def get_qdrant_client():
    global _qdrant_client
    if _qdrant_client is None:
        try:
            _qdrant_client = QdrantClient(url=settings.qdrant_url, timeout=3.0)
        except Exception as e:
            logger.warning(f"Failed to initialize QdrantClient at {settings.qdrant_url}: {e}")
            _qdrant_client = None
    return _qdrant_client


def init_qdrant_collection():
    """
    Initializes the Qdrant collection and populates it with reference facts
    using dummy 1-dimensional vectors, enabling active database search without
    loading heavy embedding model libraries on resource-constrained nodes.
    """
    client = get_qdrant_client()
    if not client:
        logger.warning("Qdrant client offline. Skipping database initialization.")
        return
    try:
        collections = client.get_collections()
        col_names = [c.name for c in collections.collections]
        
        if settings.qdrant_collection not in col_names:
            logger.info(f"Collection '{settings.qdrant_collection}' not found. Initializing in Qdrant...")
            client.recreate_collection(
                collection_name=settings.qdrant_collection,
                vectors_config=VectorParams(size=1, distance=Distance.COSINE)
            )
            
            # Populate collection with facts as payloads
            points = []
            for idx, (key, value) in enumerate(MOCK_KNOWLEDGE.items()):
                points.append(
                    PointStruct(
                        id=idx,
                        vector=[0.0],
                        payload={"text": f"[Qdrant DB Source: {key}] {value}"}
                    )
                )
            
            client.upsert(
                collection_name=settings.qdrant_collection,
                points=points
            )
            logger.info(f"Qdrant collection '{settings.qdrant_collection}' populated with {len(points)} reference facts successfully.")
        else:
            logger.info(f"Qdrant collection '{settings.qdrant_collection}' already exists. Skipping populator.")
    except Exception as e:
        logger.warning(f"Failed to initialize and populate Qdrant collection: {e}")


# Mock data to return if Qdrant collection is missing or client is offline
MOCK_KNOWLEDGE = {
    "agentic edge stack": "The Agentic Edge Stack is a cutting-edge MLOps framework combining local multi-node Kubernetes, Ollama inference, and Qdrant distributed vector search.",
    "k3d": "k3d is a lightweight wrapper to run k3s (Rancher Lab's minimal Kubernetes distribution) in Docker, ideal for local multi-node cluster testing.",
    "hpa": "Horizontal Pod Autoscaler (HPA) automatically scales the number of pods in a deployment based on CPU metrics or custom metrics.",
    "quantization": "Quantization reduces the bit-precision of LLM weights (e.g. from FP16 to INT4 GGUF) to run models with dramatically less VRAM/RAM.",
    "argocd": "ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes that automates deployment sync from a Git repository."
}

def query_vector_store(query: Any) -> str:
    """
    Looks up facts in Qdrant. Falls back to mock dictionary lookups if Qdrant is offline.
    """
    if not isinstance(query, str):
        if isinstance(query, dict):
            if "query" in query and isinstance(query["query"], str):
                query = query["query"]
            else:
                candidates = [v for v in query.values() if isinstance(v, str) and v.lower() != "string"]
                query = candidates[0] if candidates else str(query)
        else:
            query = str(query)

    client = get_qdrant_client()
    if not client:
        return _fallback_lookup(query)

    try:
        # Check if collection exists
        collections = client.get_collections()
        col_names = [c.name for c in collections.collections]
        
        if settings.qdrant_collection not in col_names:
            logger.warning(f"Collection '{settings.qdrant_collection}' not found in Qdrant. Falling back to mocks.")
            return _fallback_lookup(query)
            
        # Search Qdrant
        # Note: Since this is a simple lookup, we can run a text/vector search.
        # If the user doesn't pass a vectorized payload, we do a basic search or return mock.
        # For simplicity, we can do a search or mock search.
        # Let's perform a dummy search or try search.
        # Since we might not have a vectorizer helper running in Python, we can do a scroll/search or just fall back if it is empty.
        results = client.scroll(
            collection_name=settings.qdrant_collection,
            limit=5
        )
        # Check if we find matches in points
        points, _ = results
        if not points:
            return _fallback_lookup(query)
            
        # Filter points by basic keyword matching as a simple mock search inside the vector data
        matched_texts = []
        for p in points:
            payload = p.payload or {}
            text = payload.get("text", "")
            if any(word in text.lower() for word in query.lower().split()):
                matched_texts.append(text)
                
        if matched_texts:
            return " | ".join(matched_texts)
        else:
            return _fallback_lookup(query)

    except Exception as e:
        logger.warning(f"Qdrant query failed: {e}. Falling back to mocks.")
        return _fallback_lookup(query)

def _fallback_lookup(query: str) -> str:
    query_lower = query.lower()
    for key, value in MOCK_KNOWLEDGE.items():
        if key in query_lower:
            return f"[Mock Source: {key}] {value}"
    return "[Mock Source: None] No specific knowledge matched. Proceeding with standard LLM responses."
