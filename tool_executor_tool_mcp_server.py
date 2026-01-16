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


@mcp.tool(description="Recursively deletes all .bak files starting from a directory. Use this to clean up the workspace after successful operations.")
def clean_backups(path: str) -> str:
    return _post("/clean-backups", {"path": os.path.abspath(path)})


@mcp.tool(description="Recursively searches for a text pattern in file contents. PREFERRED for finding usages of symbols across the project.")
def search_text(path: str, pattern: str) -> str:
    return _post("/search-text", {"path": os.path.abspath(path), "pattern": pattern})


@mcp.tool(description="Recursively finds files matching a pattern. Ideal for locating files based on name structure.")
def find_files(path: str, pattern: str) -> str:
    return _post("/find-files", {"path": os.path.abspath(path), "pattern": pattern})


@mcp.tool(description="Lists files and subdirectories within a directory. Use this for initial situational awareness of a service's structure.")
def read_directory(path: str) -> str:
    return _post("/read-directory", {"path": os.path.abspath(path)})


@mcp.tool(description="Reads the content of a file from the workspace. Always read files before modifying them.")
def read_file(path: str) -> str:
    return _post("/read", {"path": os.path.abspath(path)})


@mcp.tool(description="Writes content to a file. Automatically applies project-mandatory headers and creates a .bak backup.")
def write_file(path: str, content: str) -> str:
    return _post("/write", {"path": os.path.abspath(path), "content": content})


@mcp.tool(description="Replaces a whole word in a file, respecting alphanumeric boundaries. Use this for safe variable/struct renaming.")
def replace_whole_word(path: str, old_word: str, new_word: str) -> str:
    return _post(
        "/replace-word",
        {"path": os.path.abspath(path), "old": old_word, "new": new_word},
    )


@mcp.tool(description="Performs global text replacement in a file. Use with caution for multi-line or complex string changes.")
def replace_text(path: str, old_text: str, new_text: str) -> str:
    return _post(
        "/replace-text",
        {"path": os.path.abspath(path), "old": old_text, "new": new_text},
    )


@mcp.tool(description="Updates the shared Agent Coordination Database with a new entry. Mandatory at the start and completion of every task.")
def update_agents_db(
    alias: str, intent: str, status: str, semaphore: str = "", notes: str = ""
) -> str:
    payload = {
        "alias": alias,
        "intent": intent,
        "status": status,
        "semaphore": semaphore,
        "notes": notes,
    }
    return _post("/agents/update", payload)


@mcp.tool(description="Reads the most recent entries from the Agent Coordination Database for broad synchronization.")
def read_agents_db(limit: int = 20) -> str:
    return _post("/agents/read", {"limit": limit})


@mcp.tool(description="Peeks at the 5 most recent entries from the Agent Coordination Database. Use for instant awareness of the workspace story.")
def peek_agents_db() -> str:
    return _post("/agents/peek", {})


@mcp.tool(description="Searches the Agent Coordination Database for specific keywords in alias, intent, or notes.")
def search_agents_db(query: str, limit: int = 20) -> str:
    return _post("/agents/search", {"query": query, "limit": limit})


@mcp.tool(description="Generates a high-integrity commit message via Gemini and applies it to the staged changes.")
def agent_commit(path: str, context: str) -> str:
    return _post("/git/commit", {"path": os.path.abspath(path), "context": context})


@mcp.tool(description="Pushes local commits to the remote repository. Ensure commit standards are met first.")
def agent_push(path: str) -> str:
    return _post("/git/push", {"path": os.path.abspath(path)})


@mcp.tool(description="Removes a file from the git index (cache) but keeps it in the local workspace. Ideal for fixing accidentally tracked binaries.")
def agent_git_rm_cached(path: str, file_path: str) -> str:
    """Removes a file from the git index.



    Args:

        path: The path to the git repository.

        file_path: The path to the file to remove from the index (relative to repository root).



    Returns:

        A success message or an error description.

    """

    return _post(
        "/git/rm-cached",
        {"path": os.path.abspath(path), "file_path": file_path},
    )


@mcp.tool(description="Creates a temporary checkpoint commit of all changes (staged and unstaged) and logs it to the database for cross-agent visibility.")
def agent_checkpoint(path: str, alias: str, notes: str = "") -> str:
    return _post(
        "/git/checkpoint", {"path": os.path.abspath(path), "alias": alias, "notes": notes}
    )


@mcp.tool(description="Retrieves a list of recent checkpoints for a specific repository from the coordination database.")
def list_checkpoints(path: str, limit: int = 10) -> str:
    return _post("/git/checkpoints/list", {"path": os.path.abspath(path), "limit": limit})


@mcp.tool(description="Returns the git diff between two checkpoints. Useful for reviewing changes before rollback.")
def agent_diff(path: str, base_checkpoint: str, target_checkpoint: str) -> str:
    """Returns the git diff between two checkpoints.



    Args:

        path: The path to the git repository.

        base_checkpoint: The hash of the starting point.

        target_checkpoint: The hash of the ending point.



    Returns:

        The raw git diff output.

    """

    return _post(
        "/git/diff",
        {"path": os.path.abspath(path), "base": base_checkpoint, "target": target_checkpoint},
    )


@mcp.tool(description="Restores the repository to a previous checkpoint state. Use immediately if a build fails or logic becomes corrupted.")
def agent_rollback(path: str, checkpoint_id: str) -> str:
    return _post(
        "/git/rollback", {"path": os.path.abspath(path), "checkpoint_id": checkpoint_id}
    )


if __name__ == "__main__":
    mcp.run()
