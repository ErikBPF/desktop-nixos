import json
import os
from datetime import timedelta

from authentik.core.models import Token, TokenIntents, User, default_token_key
from django.utils.timezone import now

action = os.environ["AUTHENTIK_TOKEN_ACTION"]

if action == "revoke":
    tokens = Token.objects.including_expired().filter(
        identifier="bootstrap-homelab-iac-authentik-config-manager"
    )
    deleted, _ = tokens.delete()
    print(f"AUTHENTIK_ADMIN_TOKEN={json.dumps({'revoked': deleted == 1})}")
elif action == "create":
    tokens = Token.objects.including_expired().filter(
        identifier="bootstrap-homelab-iac-authentik-config-manager"
    )
    tokens.delete()
    token = Token.objects.create(
        identifier="bootstrap-homelab-iac-authentik-config-manager",
        intent=TokenIntents.INTENT_API,
        user=User.objects.get(username="akadmin"),
        description="Temporary Authentik config-manager bootstrap token",
        expiring=True,
        expires=now() + timedelta(minutes=15),
    )
    print(f"AUTHENTIK_ADMIN_TOKEN={json.dumps({'token': token.key})}")
elif action == "rotate-iac":
    service_account = User.objects.get(
        username="svc-homelab-iac-authentik-config-manager"
    )
    if service_account.type not in ("service_account", "internal_service_account"):
        raise ValueError("Authentik config manager is not a service account")
    if service_account.is_superuser:
        raise ValueError("Authentik config manager must not be a superuser")
    token, _ = Token.objects.including_expired().update_or_create(
        identifier="svc-homelab-iac-authentik-config-manager-api-token",
        defaults={
            "intent": TokenIntents.INTENT_API,
            "user": service_account,
            "description": "Dedicated Authentik config-manager provider token",
            "expiring": True,
            "expires": now() + timedelta(days=90),
        },
    )
    token.key = default_token_key()
    token.save(update_fields=["key"])
    print(f"AUTHENTIK_IAC_TOKEN={json.dumps({'token': token.key})}")
else:
    raise ValueError("AUTHENTIK_TOKEN_ACTION must be create, revoke, or rotate-iac")
