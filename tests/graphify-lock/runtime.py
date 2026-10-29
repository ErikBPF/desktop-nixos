"""Exercise native wheel loading with the built Graphify interpreter."""

from pathlib import Path
import subprocess
import sys

package = Path(sys.argv[1])
result = subprocess.run([str(package / "bin/python"), "-I", "-c", """
import graphify, mcp, numpy, rapidfuzz, tree_sitter, tree_sitter_python
assert numpy.dot([1, 2], [3, 4]) == 11
assert rapidfuzz.fuzz.ratio('locked', 'locked') == 100
tree_sitter.Language(tree_sitter_python.language())
"""], text=True, capture_output=True)
assert result.returncode == 0, result.stderr
result = subprocess.run([str(package / "bin/graphify"), "--version"],
                        text=True, capture_output=True)
assert result.returncode == 0, result.stderr
assert result.stdout.startswith("graphify "), result.stdout
print("Graphify CLI and native wheel operations pass")
