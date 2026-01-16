# DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

import os
import json
import urllib.request
from typing import Dict, Any, Optional
from fastmcp import FastMCP

# Configuration
SERVER_URL = os.getenv("TOOL_EXECUTOR_URL", "http://localhost:9091")

# Initialize MCP
mcp = FastMCP("tool_executor")


def _post(path: str, data: Dict[str, Any]) -> str:
    """Helper to send POST requests to the Zig Tool Executor service."""
    url = f"{SERVER_URL}{path}"
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as response:
            return response.read().decode("utf-8")
    except Exception as e:
        return f"Error connecting to Tool Executor at {url}: {str(e)}"


@mcp.tool()
def clean_backups(path: str) -> str:
    """Recursively deletes all .bak files starting from a directory."""
    return _post("/clean-backups", {"path": os.path.abspath(path)})


@mcp.tool()
def search_text(path: str, pattern: str) -> str:
    """Recursively searches for a text pattern in file contents."""
    return _post("/search-text", {"path": os.path.abspath(path), "pattern": pattern})


@mcp.tool()
def find_files(path: str, pattern: str) -> str:
    """Recursively finds files matching a pattern."""
    return _post("/find-files", {"path": os.path.abspath(path), "pattern": pattern})


@mcp.tool()
def read_directory(path: str) -> str:
    """Lists files and subdirectories within a directory."""
    return _post("/read-directory", {"path": os.path.abspath(path)})


@mcp.tool()
def read_file(path: str) -> str:
    """Reads the content of a file from the workspace."""
    return _post("/read", {"path": os.path.abspath(path)})


@mcp.tool()
def write_file(path: str, content: str) -> str:
    """Writes content to a file with mandatory headers and backups."""
    return _post("/write", {"path": os.path.abspath(path), "content": content})


@mcp.tool()
def replace_whole_word(path: str, old_word: str, new_word: str) -> str:
    """Replaces a whole word in a file, respecting alphanumeric boundaries."""
    return _post(
        "/replace-word",
        {"path": os.path.abspath(path), "old": old_word, "new": new_word},
    )


@mcp.tool()
def replace_text(path: str, old_text: str, new_text: str) -> str:
    """Performs global text replacement in a file."""
    return _post(
        "/replace-text",
        {"path": os.path.abspath(path), "old": old_text, "new": new_text},
    )


@mcp.tool()
def update_agents_db(
    alias: str, intent: str, status: str, semaphore: str = "", notes: str = ""
) -> str:
    """Updates the shared Agent Coordination Database with a new entry."""
    payload = {
        "alias": alias,
        "intent": intent,
        "status": status,
        "semaphore": semaphore,
        "notes": notes,
    }
    return _post("/agents/update", payload)


@mcp.tool()
def read_agents_db(limit: int = 20) -> str:
    """Reads the most recent entries from the Agent Coordination Database."""
    return _post("/agents/read", {"limit": limit})


@mcp.tool()
def peek_agents_db() -> str:
    """Peeks at the 5 most recent entries from the Agent Coordination Database."""
    return _post("/agents/peek", {})


@mcp.tool()
def search_agents_db(query: str, limit: int = 20) -> str:
    """Searches the Agent Coordination Database for specific keywords."""
    return _post("/agents/search", {"query": query, "limit": limit})


@mcp.tool()
def agent_commit(path: str, context: str) -> str:
    """Generates a high-integrity commit message and applies it."""
    return _post("/git/commit", {"path": os.path.abspath(path), "context": context})


@mcp.tool()
def agent_push(path: str) -> str:
    """Pushes local commits to the remote repository."""
    return _post("/git/push", {"path": os.path.abspath(path)})


@mcp.tool()
def agent_checkpoint(path: str, alias: str, notes: str = "") -> str:
    """Creates a temporary checkpoint commit and logs it to the database."""
    return _post(
        "/git/checkpoint", {"path": os.path.abspath(path), "alias": alias, "notes": notes}
    )


@mcp.tool()
def list_checkpoints(path: str, limit: int = 10) -> str:
    """Retrieves a list of recent checkpoints for a specific repository."""
    return _post("/git/checkpoints/list", {"path": os.path.abspath(path), "limit": limit})


@mcp.tool()
def agent_rollback(path: str, checkpoint_id: str) -> str:
    """Restores the repository to a previous checkpoint state."""
    return _post(
        "/git/rollback", {"path": os.path.abspath(path), "checkpoint_id": checkpoint_id}
    )


if __name__ == "__main__":
    mcp.run()