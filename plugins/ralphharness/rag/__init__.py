"""
RAG integration module for RalphHarness.

Implements Components 1-9 from specs/rag-integration/design.md:
  1. RAGConfig — YAML configuration loader
  2. RAGService — retrieve/index/orchestrate
  3. VectorDBProvider ABC + QdrantProvider + FAISSProvider
  4. QdrantProvider — Qdrant HTTP REST provider
  5. Embedder ABC + LocalEmbedder + OpenAIEmbedder + AzureOpenAIEmbedder
  6. FAISSProvider — local-file FAISS provider
  7. SecurityLayer — chunk sanitization at index time
  8. Bash hooks (lib-rag.sh) — rag_retrieve, rag_index_task, rag_health_check
  9. OnboardingStep ABC + 7 concrete steps for /rag-onboard
"""

import os

# Suppress huggingface_hub deprecation warning at module load time.
# Set default only if user hasn't already configured it.
os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "0")
