#!/usr/bin/env python3
import base64
import hashlib
import secrets
import string
import sys
from pathlib import Path

password = Path(sys.argv[1]).read_bytes()
if not password:
    raise SystemExit("password is empty")
iterations = 1_000_000
alphabet = string.ascii_letters + string.digits
salt = "".join(secrets.choice(alphabet) for _ in range(22))
digest = hashlib.pbkdf2_hmac("sha256", password, salt.encode(), iterations)
encoded = base64.b64encode(digest).decode()
print(f"pbkdf2_sha256${iterations}${salt}${encoded}")
