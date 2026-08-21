import os
import time
from datetime import datetime, timezone

import functions_framework
from google.cloud import firestore
from google.cloud import compute_v1
from rcon.source import Client as RconClient

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
ZONE = os.environ["GCP_ZONE"]
INSTANCE_NAME = os.environ["INSTANCE_NAME"]
RCON_PORT = int(os.environ["RCON_PORT"])
GRACE_PERIOD_SECONDS = int(os.environ.get("GRACE_PERIOD_SECONDS", 600))   # 10 min default
IDLE_TIMEOUT_SECONDS = int(os.environ.get("IDLE_TIMEOUT_SECONDS", 1800))  # 30 min default

STATE_DOC_PATH = ("server_state", "idle_checker")


def _get_rcon_password():
    from google.cloud import secretmanager
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/zomboid-rcon-password/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")


def _get_instance_info():
    """Returns (status, internal_ip, last_start_timestamp) for the VM, fresh each call."""
    client = compute_v1.InstancesClient()
    instance = client.get(project=PROJECT_ID, zone=ZONE, instance=INSTANCE_NAME)
    status = instance.status  # e.g. "RUNNING", "TERMINATED"
    internal_ip = None
    if instance.network_interfaces:
        internal_ip = instance.network_interfaces[0].network_i_p
    last_start = instance.last_start_timestamp  # RFC3339 string
    return status, internal_ip, last_start


def _stop_instance():
    client = compute_v1.InstancesClient()
    operation = client.stop(project=PROJECT_ID, zone=ZONE, instance=INSTANCE_NAME)
    return operation


def _get_player_count(internal_ip, rcon_password):
    with RconClient(internal_ip, RCON_PORT, passwd=rcon_password, timeout=10) as client:
        response = client.run("players")
    # PZ's "players" command returns a header line with a count, e.g.
    # "Players connected (2):" followed by "-Name" lines
    lines = [line.strip() for line in response.splitlines() if line.strip()]
    player_lines = [line for line in lines if line.startswith("-")]
    return len(player_lines)


@functions_framework.http
def check_idle(request):
    db = firestore.Client()
    doc_ref = db.collection(STATE_DOC_PATH[0]).document(STATE_DOC_PATH[1])

    status, internal_ip, last_start = _get_instance_info()

    if status != "RUNNING":
        return f"VM status is {status}, nothing to do.", 200

    now = datetime.now(timezone.utc)
    state = doc_ref.get()
    state_data = state.to_dict() if state.exists else {}

    stored_boot_time = state_data.get("last_boot_time")

    # New boot detected (or first run ever) -- reset the clock, don't stop this run
    if stored_boot_time != last_start:
        doc_ref.set({
            "last_boot_time": last_start,
            "last_active_time": now.isoformat(),
        })
        return f"New boot detected ({last_start}) -- resetting idle clock.", 200

    boot_dt = datetime.fromisoformat(last_start.replace("Z", "+00:00"))
    seconds_since_boot = (now - boot_dt).total_seconds()

    if seconds_since_boot < GRACE_PERIOD_SECONDS:
        return f"Within grace period ({seconds_since_boot:.0f}s since boot), skipping.", 200

    try:
        rcon_password = _get_rcon_password()
        player_count = _get_player_count(internal_ip, rcon_password)
    except Exception as e:
        # If RCON is unreachable (e.g. server still finishing boot), don't stop --
        # err on the side of leaving it running rather than risk a false shutdown.
        return f"Could not reach RCON ({e}), skipping this run.", 200

    if player_count > 0:
        doc_ref.update({"last_active_time": now.isoformat()})
        return f"{player_count} player(s) online, resetting idle clock.", 200

    last_active_str = state_data.get("last_active_time", now.isoformat())
    last_active_dt = datetime.fromisoformat(last_active_str)
    seconds_idle = (now - last_active_dt).total_seconds()

    if seconds_idle >= IDLE_TIMEOUT_SECONDS:
        _stop_instance()
        return f"Idle for {seconds_idle:.0f}s -- stopping VM.", 200

    return f"No players, idle for {seconds_idle:.0f}s (under {IDLE_TIMEOUT_SECONDS}s threshold).", 200