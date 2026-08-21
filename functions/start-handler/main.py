import os
import json

import functions_framework
from flask import jsonify
import nacl.signing
import nacl.exceptions
import urllib.request

DISCORD_PUBLIC_KEY = os.environ["DISCORD_PUBLIC_KEY"]
PROJECT_ID = os.environ["GCP_PROJECT_ID"]
ZONE = os.environ["GCP_ZONE"]
INSTANCE_NAME = os.environ["INSTANCE_NAME"]

verify_key = nacl.signing.VerifyKey(bytes.fromhex(DISCORD_PUBLIC_KEY))

COMPUTE_API_BASE = f"https://compute.googleapis.com/compute/v1/projects/{PROJECT_ID}/zones/{ZONE}/instances/{INSTANCE_NAME}"


def _verify_signature(request):
    signature = request.headers.get("X-Signature-Ed25519")
    timestamp = request.headers.get("X-Signature-Timestamp")
    body = request.get_data(as_text=True)

    if signature is None or timestamp is None:
        return False

    try:
        verify_key.verify(f"{timestamp}{body}".encode(), bytes.fromhex(signature))
        return True
    except nacl.exceptions.BadSignatureError:
        return False


def _get_access_token():
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        return json.loads(response.read())["access_token"]


def _compute_api_request(method, url_suffix=""):
    token = _get_access_token()
    req = urllib.request.Request(
        COMPUTE_API_BASE + url_suffix,
        headers={"Authorization": f"Bearer {token}"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        return json.loads(response.read())


def _handle_start_command():
    instance = _compute_api_request("GET")
    status = instance.get("status")

    if status == "RUNNING":
        message = "The server's already running!"
    elif status in ("PROVISIONING", "STAGING"):
        message = "The server's already starting up."
    else:
        _compute_api_request("POST", "/start")
        message = "Starting the server, give it a few minutes."

    return jsonify({"type": 4, "data": {"content": message}})


@functions_framework.http
def handle_interaction(request):
    if not _verify_signature(request):
        return "invalid request signature", 401

    payload = request.get_json(silent=True)
    if payload is None:
        return "bad request", 400

    interaction_type = payload.get("type")

    if interaction_type == 1:
        return jsonify({"type": 1})

    if interaction_type == 2:
        command_name = payload.get("data", {}).get("name")
        if command_name == "start-zomboid":
            return _handle_start_command()
        return jsonify({"type": 4, "data": {"content": f"Unknown command: {command_name}"}})

    return jsonify({"type": 4, "data": {"content": "Unsupported interaction type."}})