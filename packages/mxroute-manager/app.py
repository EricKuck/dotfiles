import os
import sys
import requests
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)
logger = app.logger

MXROUTE_SERVER = os.environ.get("MXROUTE_SERVER", "api.mxroute.com")
MXROUTE_USERNAME = os.environ.get("MXROUTE_USERNAME", "")
MXROUTE_API_KEY = os.environ.get("MXROUTE_API_KEY", "")
ALLOWED_DESTINATIONS = os.environ.get("ALLOWED_EMAILS", "").split(",")
ALLOWED_DESTINATIONS = [e.strip() for e in ALLOWED_DESTINATIONS if e.strip()]


def get_domain_from_email(email):
    if "@" in email:
        return email.split("@")[1]
    return None


def get_local_part(email):
    if "@" in email:
        return email.split("@")[0]
    return email


ALLOWED_DOMAINS = list(
    set(
        [
            get_domain_from_email(e)
            for e in ALLOWED_DESTINATIONS
            if get_domain_from_email(e)
        ]
    )
)


class MxRouteAPI:
    def __init__(self, server, username, api_key):
        self.base_url = "https://api.mxroute.com"

        self.headers = {
            "X-Server": server,
            "X-Username": username,
            "X-API-Key": api_key,
            "Accept": "application/json",
        }

    def get_forwarders(self, domain):
        url = f"{self.base_url}/domains/{domain}/forwarders"
        try:
            resp = requests.get(url, headers=self.headers, timeout=10)
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            logger.error(f"Error fetching forwarders for {domain}: {e}")
            return []

    def add_forwarder(self, domain, alias, forward_to):
        url = f"{self.base_url}/domains/{domain}/forwarders"
        data = {"alias": alias, "destinations": [forward_to]}

        headers = self.headers.copy()
        headers["Content-Type"] = "application/json"

        try:
            resp = requests.post(url, headers=headers, json=data, timeout=10)
            resp.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Error adding forwarder {alias}@{domain}: {e}")
            return False

    def delete_forwarder(self, domain, alias):
        url = f"{self.base_url}/domains/{domain}/forwarders/{alias}"
        try:
            resp = requests.delete(url, headers=self.headers, timeout=10)
            resp.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Error deleting forwarder {alias}@{domain}: {e}")
            return False


api = MxRouteAPI(MXROUTE_SERVER, MXROUTE_USERNAME, MXROUTE_API_KEY)


@app.route("/")
def index():
    return render_template(
        "index.html",
        allowed_destinations=ALLOWED_DESTINATIONS,
    )


@app.route("/api/forwarders")
def get_forwarders():
    destination = request.args.get("destination")

    if not destination:
        return jsonify({"forwarders": []})

    if destination not in ALLOWED_DESTINATIONS:
        return jsonify({"error": "Invalid destination"}), 400

    all_forwarders = []

    # Iterate over derived domains
    for domain_name in ALLOWED_DOMAINS:
        fwds = api.get_forwarders(domain_name)

        for fwd in fwds["data"]:
            # Only include forwarders that match the selected destination
            if fwd["destinations"][0] == destination:
                all_forwarders.append(
                    {
                        "forwarder": fwd["alias"],
                        "destination": fwd["destinations"][0],
                        "domain": domain_name,
                        "full_email": fwd["email"],
                    }
                )

    return jsonify({"forwarders": all_forwarders})


@app.route("/api/add", methods=["POST"])
def add_forwarder():
    data = request.json
    email = data.get("email")
    forward_to = data.get("forward_to")

    if not email or not forward_to:
        return jsonify({"error": "Missing fields"}), 400

    if forward_to not in ALLOWED_DESTINATIONS:
        return jsonify({"error": "Destination email not in allowed list"}), 403

    if "@" not in email:
        dest_domain = get_domain_from_email(forward_to)
        email = f"{email}@{dest_domain}"

    domain = get_domain_from_email(email)
    alias = get_local_part(email)

    success = api.add_forwarder(domain, alias, forward_to)
    if success:
        return jsonify({"success": True})
    else:
        return jsonify({"error": "Failed to add forwarder"}), 500


@app.route("/api/delete", methods=["POST"])
def delete_forwarder():
    data = request.json
    email = data.get("email")

    if not email:
        return jsonify({"error": "Missing email"}), 400

    domain = get_domain_from_email(email)
    alias = get_local_part(email)

    success = api.delete_forwarder(domain, alias)
    if success:
        return jsonify({"success": True})
    else:
        return jsonify({"error": "Failed to delete forwarder"}), 500


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "2121"))
    app.run(host=host, port=port, debug=False)
