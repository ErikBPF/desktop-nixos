import json
import os
from datetime import timedelta

from authentik.core.models import Token, TokenIntents, User, default_token_key
from django.utils.timezone import now

action = os.environ["AUTHENTIK_TOKEN_ACTION"]

if action == "revoke":
    tokens = Token.objects.including_expired().filter(identifier="homelab-iac-bootstrap")
    deleted, _ = tokens.delete()
    print(f"AUTHENTIK_ADMIN_TOKEN={json.dumps({'revoked': deleted == 1})}")
elif action == "create":
    tokens = Token.objects.including_expired().filter(identifier="homelab-iac-bootstrap")
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
elif action == "rotate-iac":
    token, _ = Token.objects.including_expired().update_or_create(
        identifier="homelab-iac",
        defaults={
            "intent": TokenIntents.INTENT_API,
            "user": User.objects.get(username="homelab-iac"),
            "description": "Dedicated homelab-iac provider token",
            "expiring": False,
        },
    )
    token.key = default_token_key()
    token.save(update_fields=["key"])
    print(f"AUTHENTIK_IAC_TOKEN={json.dumps({'token': token.key})}")
else:
    raise ValueError("AUTHENTIK_TOKEN_ACTION must be create, revoke, or rotate-iac")
