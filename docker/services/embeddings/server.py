"""FastAPI service that wraps a sentence-transformers model.

Single endpoint surface so the Ruby side stays simple:

  POST /v1/embed         — embed a list of texts (batched internally)
  GET  /v1/health        — readiness probe
  GET  /v1/info          — model + dimension introspection

The "task" parameter handles the e5-family prefix convention transparently
("query: " for queries, "passage: " for documents). Embeddings are L2-normalized
so cosine similarity collapses to a dot product on the consumer side.
"""

import os
from typing import List, Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from sentence_transformers import SentenceTransformer

MODEL_NAME = os.environ.get("MODEL_NAME", "intfloat/multilingual-e5-base")
HF_HOME = os.environ.get("HF_HOME", "/models")
MAX_BATCH = int(os.environ.get("EMBEDDINGS_MAX_BATCH", "256"))

app = FastAPI(title="Monadic Embeddings", version="1.0.0")
model = SentenceTransformer(MODEL_NAME, cache_folder=HF_HOME)
DIMENSION = int(model.get_sentence_embedding_dimension())
MAX_SEQ_LENGTH = int(model.get_max_seq_length())


class EmbedRequest(BaseModel):
    texts: List[str] = Field(..., min_length=1)
    task: Literal["passage", "query", "raw"] = "passage"


class EmbedResponse(BaseModel):
    vectors: List[List[float]]
    model: str
    dimension: int


def _prefix(text: str, task: str) -> str:
    if task == "raw":
        return text
    if task == "query":
        return f"query: {text}"
    return f"passage: {text}"


@app.get("/v1/health")
def health():
    return {"status": "ok", "model": MODEL_NAME, "dimension": DIMENSION}


@app.get("/v1/info")
def info():
    return {
        "model": MODEL_NAME,
        "dimension": DIMENSION,
        "max_seq_length": MAX_SEQ_LENGTH,
        "max_batch_size": MAX_BATCH,
        "normalized": True,
    }


@app.post("/v1/embed", response_model=EmbedResponse)
def embed(req: EmbedRequest):
    if len(req.texts) > MAX_BATCH:
        raise HTTPException(
            status_code=413,
            detail=f"batch size {len(req.texts)} exceeds max {MAX_BATCH}; split client-side",
        )
    inputs = [_prefix(t, req.task) for t in req.texts]
    vectors = model.encode(
        inputs,
        normalize_embeddings=True,
        show_progress_bar=False,
        convert_to_numpy=True,
    )
    return EmbedResponse(
        vectors=vectors.tolist(),
        model=MODEL_NAME,
        dimension=DIMENSION,
    )
