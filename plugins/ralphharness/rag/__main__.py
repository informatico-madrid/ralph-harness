"""CLI entry point for the RAG integration module.

Usage: python -m plugins.ralphharness.rag <command> [options]

Subcommands: retrieve, index, index-all, doctor, search, onboard
"""

import argparse
import json
import sys


def _print_stub(**kwargs):
    """Print a JSON stub and exit successfully."""
    result = {"stub": True, **kwargs}
    print(json.dumps(result))
    sys.exit(0)


def cmd_retrieve(args):
    """Retrieve subcommand — wire to RAGService."""
    from time import time

    from .service import RAGService

    start = time()
    service = RAGService.from_config()

    if service is None:
        print("[]")
        sys.exit(0)

    try:
        results = service.retrieve(args.query, args.collection, args.top_k)
    except Exception as e:
        print(f"[]", file=sys.stderr)
        import logging

        logging.getLogger("rag").warning("Retrieve failed: %s", e)
        print("[]")
        sys.exit(0)

    latency_ms = (time() - start) * 1000

    if not results:
        print("[]")
        sys.exit(0)

    # Build JSON response
    provider_name = type(service._provider).__name__.lower()
    embedder_name = type(service._embedder).__name__.lower()

    chunks = []
    for r in results:
        chunks.append(
            {
                "content": r.content[:500],  # Truncate for CLI output
                "source_path": r.source_path,
                "score": r.score,
            }
        )

    envelope = {
        "provider_used": provider_name,
        "embedder_used": embedder_name,
        "latency_ms": round(latency_ms, 1),
        "results": chunks,
    }
    print(json.dumps(envelope))
    sys.exit(0)


def cmd_index(args):
    """Stub index command."""
    _print_stub(command="index")


def cmd_index_all(args):
    """Stub index-all command."""
    _print_stub(command="index-all")


def cmd_doctor(args):
    """Doctor command: print tiered health report."""
    from plugins.ralphharness.rag.config import RAGConfig

    config = RAGConfig.load()

    checks = []

    # enabled
    if config.enabled:
        checks.append("OK     enabled: true")
    else:
        checks.append("WARN   enabled: false (RAG is disabled)")

    # provider
    checks.append(f"OK     provider: {config.provider}")

    # embedder
    embedder_status = "OK"
    if config.embedder.provider == "local":
        checks.append(f"OK     embeddings.provider: local (sentence-transformers)")
    elif config.embedder.provider == "openai":
        if config.embedder.api_key:
            checks.append(f"OK     embeddings.provider: openai (key configured)")
        else:
            embedder_status = "WARN"
            checks.append(f"WARN   embeddings.provider: openai (no API key configured)")
    elif config.embedder.provider == "azure":
        if config.embedder.azure_endpoint:
            checks.append(f"OK     embeddings.provider: azure (endpoint configured)")
        else:
            embedder_status = "WARN"
            checks.append(f"WARN   embeddings.provider: azure (no endpoint configured)")
    else:
        checks.append(f"WARN   embeddings.provider: unknown ({config.embedder.provider})")

    # endpoints
    if config.provider == "qdrant":
        if config.vector_db.endpoint:
            checks.append(f"OK     vector_db.endpoint: {config.vector_db.endpoint}")
        else:
            checks.append("WARN   vector_db.endpoint: not configured (will use default)")
    elif config.provider == "faiss":
        if config.vector_db.faiss_index_path:
            checks.append(f"OK     faiss.index_path: {config.vector_db.faiss_index_path}")
        else:
            checks.append("WARN   faiss.index_path: not configured")

    report = "\n".join(checks)
    print(report)
    sys.exit(0)


def cmd_search(args):
    """Stub search command."""
    _print_stub(command="search")


def cmd_onboard(args):
    """Stub onboard command."""
    _print_stub(command="onboard")


def main():
    parser = argparse.ArgumentParser(
        prog="plugins.ralphharness.rag",
        description="RAG integration for RalphHarness",
    )
    subparsers = parser.add_subparsers(dest="command")

    # retrieve
    retrieve_parser = subparsers.add_parser("retrieve", help="Retrieve relevant chunks")
    retrieve_parser.add_argument("--query", required=True, help="Search query")
    retrieve_parser.add_argument("--collection", required=True, help="Target collection")
    retrieve_parser.add_argument("--top-k", type=int, default=3, help="Number of results")
    retrieve_parser.set_defaults(func=cmd_retrieve)

    # index
    index_parser = subparsers.add_parser("index", help="Index chunks")
    index_parser.add_argument("--source", required=True, help="Source file or directory")
    index_parser.add_argument("--collection", required=True, help="Target collection")
    index_parser.add_argument("--spec-name", required=True, help="Spec name")
    index_parser.set_defaults(func=cmd_index)

    # index-all
    index_all_parser = subparsers.add_parser(
        "index-all", help="Index all specs"
    )
    index_all_parser.add_argument(
        "--force", action="store_true", help="Force re-indexing"
    )
    index_all_parser.add_argument(
        "--dry-run", action="store_true", help="Preview without writing"
    )
    index_all_parser.set_defaults(func=cmd_index_all)

    # doctor
    doctor_parser = subparsers.add_parser("doctor", help="Health check and diagnostics")
    doctor_parser.set_defaults(func=cmd_doctor)

    # search
    search_parser = subparsers.add_parser("search", help="Interactive search")
    search_parser.add_argument("--query", required=True, help="Search query")
    search_parser.set_defaults(func=cmd_search)

    # onboard
    onboard_parser = subparsers.add_parser("onboard", help="Interactive onboarding")
    onboard_parser.add_argument(
        "--non-interactive", action="store_true", help="Non-interactive mode"
    )
    onboard_parser.set_defaults(func=cmd_onboard)

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
