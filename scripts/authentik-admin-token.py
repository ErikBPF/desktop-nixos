import json
import os
from datetime import timedelta

from authentik.core.models import Token, TokenIntents, User
from django.utils.timezone import now

action = os.environ["AUTHENTIK_TOKEN_ACTION"]
tokens = Token.objects.including_expired().filter(identifier="homelab-iac-bootstrap")

if action == "revoke":
    deleted, _ = tokens.delete()
    print(f"AUTHENTIK_ADMIN_TOKEN={json.dumps({'revoked': deleted == 1})}")
elif action == "create":
    tokens.delete()
    token = Token.objects.create(
        identifier="homelab-iac-bootstrap",
        intent=TokenIntents.INTENT_API,
        user=User.objects.get(username="akadmin"),
        description="Temporary homelab-iac bootstrap token",
        expiring=True,
        expires=now() + timedelta(minutes=15),
    )
    print(f"AUTHENTIK_ADMIN_TOKEN={json.dumps({'token': token.key})}")
else:
    raise ValueError("AUTHENTIK_TOKEN_ACTION must be create or revoke")
