import os
import sys
from pathlib import Path

# The app runs with /app on the path inside the container, so imports are
# flat (`import db`, not `from app import db`). Mirror that here rather than
# adding package plumbing that only exists to satisfy the test runner.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("LOG_LEVEL", "WARNING")
