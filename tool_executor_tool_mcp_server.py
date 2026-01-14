# DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

import os
import json
import urllib.request
from typing import List, Optional, Dict, Any
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
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as response:
            return response.read().decode("utf-8")
    except Exception as e:
        return f"Error connecting to Tool Executor at {url}: {str(e)}"

@mcp.tool()

def search_text(path: str, pattern: str) -> str:

    """Recursively searches for a text pattern in file contents.



    Args:

        path: The absolute path to the directory to search within.

        pattern: The pattern to search for within files.



    Returns:

        A JSON string containing an array of matching file paths.

    """

    return _post("/search-text", {"path": os.path.abspath(path), "pattern": pattern})



@mcp.tool()

def find_files(path: str, pattern: str) -> str:

    """Recursively finds files matching a pattern.



    Args:

        path: The absolute path to the directory to search within.

        pattern: The pattern to match against filenames.



    Returns:

        A JSON string containing an array of matching file paths.

    """

    return _post("/find-files", {"path": os.path.abspath(path), "pattern": pattern})



@mcp.tool()

def read_directory(path: str) -> str:

    """Lists files and subdirectories within a directory.



    Args:

        path: The relative or absolute path to the directory to list.



    Returns:

        A JSON string containing an array of directory entries.

    """

    return _post("/read-directory", {"path": os.path.abspath(path)})



@mcp.tool()

def read_file(path: str) -> str:

    """Reads the content of a file from the workspace.



    Args:

        path: The relative or absolute path to the file to be read.



    Returns:

        The literal content of the file.

    """

    return _post("/read", {"path": os.path.abspath(path)})



@mcp.tool()

def write_file(path: str, content: str) -> str:

    """Writes content to a file, ensuring mandatory headers are applied.



    This tool automatically adds the project's mandatory 14-value header

    to .zig, .go, .js, and .ts files if it's missing. It also creates a 

    backup (.bak) before writing.



    Args:

        path: The path where the file should be written.

        content: The text content to write into the file.



    Returns:

        A success message or an error description.

    """

    return _post("/write", {"path": os.path.abspath(path), "content": content})



@mcp.tool()

def replace_whole_word(path: str, old_word: str, new_word: str) -> str:

    """Replaces a whole word in a file, respecting alphanumeric boundaries.



    This ensures that replacing 'ctx' won't accidentally change 'context'.



    Args:

        path: The path to the file to modify.

        old_word: The exact word to find.

        new_word: The word to replace it with.



    Returns:

        A success message or an error description.

    """

    return _post("/replace-word", {"path": os.path.abspath(path), "old": old_word, "new": new_word})



@mcp.tool()

def replace_text(path: str, old_text: str, new_text: str) -> str:

    """Performs global text replacement in a file.



    Args:

        path: The path to the file to modify.

        old_text: The literal text to find.

        new_text: The text to replace it with.



    Returns:

        A success message or an error description.

    """

    return _post("/replace-text", {"path": os.path.abspath(path), "old": old_text, "new": new_text})



@mcp.tool()

def update_agents_db(alias: str, intent: str, status: str, semaphore: str = "", notes: str = "") -> str:

    """Updates the shared Agent Coordination Database with a new entry.



    Use this tool at the start and throughout tasks to synchronize with other agents.

    It replaces the manual AGENT_CHAT.md coordination.



    Args:

        alias: Your creative agent alias (e.g., 'Migration Whisperer').

        intent: The high-level goal of your current action.

        status: Current state (e.g., 'PLANNING', 'EXECUTING', 'COMPLETED').

        semaphore: A description of the files or logic you are currently locking.

        notes: Any additional collaboration notes for other agents.



    Returns:

        A success message or an error description.

    """

    payload = {

        "alias": alias,

        "intent": intent,

        "status": status,

        "semaphore": semaphore,

        "notes": notes

    }

    return _post("/agents/update", payload)



@mcp.tool()

def read_agents_db(limit: int = 20) -> str:

    """Reads the most recent entries from the Agent Coordination Database.



    Args:

        limit: The number of recent entries to retrieve. Defaults to 20.



    Returns:

        A JSON string containing an array of recent agent chat entries.

    """

    return _post("/agents/read", {"limit": limit})



@mcp.tool()

def search_agents_db(query: str, limit: int = 20) -> str:

    """Searches the Agent Coordination Database for specific keywords.



    Searches across alias, intent, and notes fields for the given query string.



    Args:

        query: The keyword or phrase to search for.

        limit: The maximum number of matches to return. Defaults to 20.



    Returns:

        A JSON string containing an array of matching agent chat entries.

    """

    return _post("/agents/search", {"query": query, "limit": limit})



@mcp.tool()

def agent_commit(path: str, context: str) -> str:

    """Generates a high-integrity commit message and applies it.



    This tool automatically fetches staged changes (git diff --cached),

    generates a commit message using Gemini following the project template,

    and executes the commit.



    Args:

        path: The path to the git repository.

        context: A brief description of what was done to guide the message generation.



    Returns:

        A success message or an error description.

    """

    return _post("/git/commit", {"path": os.path.abspath(path), "context": context})



@mcp.tool()

def agent_push(path: str) -> str:

    """Pushes local commits to the remote repository.



    Args:

        path: The path to the git repository.



    Returns:

        A success message or an error description.

    """

    return _post("/git/push", {"path": os.path.abspath(path)})

if __name__ == "__main__":
    mcp.run()