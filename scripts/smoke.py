#!/usr/bin/env python3
"""
End-to-end smoke test against a running whelx, acting as a WhatsApp Cloud API client app.

Starts a local webhook receiver that verifies X-Hub-Signature-256, seeds a
scenario through the control API and drives the Graph API exactly like
a typical Cloud API client does. Exits non-zero on the first failure.

Usage:
    python3 scripts/smoke.py [--base http://localhost:4000] [--port 8765]

Only uses the Python standard library.
"""

import argparse
import hashlib
import hmac
import json
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_ID = "100000000000001"
SECRET = "aaaabbbbccccddddeeeeffff00001111"
VERIFY = "verify-local"
WABA = "200000000000001"
PHONE = "300000000000001"
TOKEN = "EAAsmoketoken000001"
CUSTOMER = "5511988887777"

RECEIVED = []
LOCK = threading.Lock()


class Receiver(BaseHTTPRequestHandler):
    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if query.get("hub.mode") == ["subscribe"] and query.get("hub.verify_token") == [VERIFY]:
            self._reply(200, query["hub.challenge"][0])
        else:
            self._reply(403, "forbidden")

    def do_POST(self):
        body = self.rfile.read(int(self.headers["content-length"]))
        expected = "sha256=" + hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest()
        signature_ok = hmac.compare_digest(self.headers.get("x-hub-signature-256", ""), expected)
        with LOCK:
            RECEIVED.append({"sig_ok": signature_ok, "ua": self.headers.get("user-agent"), "body": json.loads(body)})
        self._reply(200 if signature_ok else 403, "OK")

    def _reply(self, status, text):
        self.send_response(status)
        self.end_headers()
        self.wfile.write(text.encode())

    def log_message(self, *args):
        pass


class Client:
    def __init__(self, base):
        self.base = base.rstrip("/")

    def call(self, method, path, body=None, headers=None, raw=None, query=None):
        url = self.base + path + ("?" + urllib.parse.urlencode(query) if query else "")
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        request = urllib.request.Request(url, data=data, method=method)
        if body is not None:
            request.add_header("content-type", "application/json")
        for key, value in (headers or {}).items():
            request.add_header(key, value)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.status, _decode(response.read())
        except urllib.error.HTTPError as error:
            return error.code, _decode(error.read())

    def graph(self, method, path, body=None, **kwargs):
        headers = {"Authorization": "Bearer " + TOKEN, **kwargs.pop("headers", {})}
        return self.call(method, "/v25.0" + path, body, headers=headers, **kwargs)

    def control(self, method, path, body=None, **kwargs):
        return self.call(method, "/_whelx" + path, body, **kwargs)


def _decode(data):
    try:
        return json.loads(data)
    except ValueError:
        return data


PASSED = []


def check(label, condition, detail=None):
    if not condition:
        print(f"  ✗ {label}")
        if detail is not None:
            print("    " + json.dumps(detail, ensure_ascii=False, default=str)[:2000])
        sys.exit(1)
    PASSED.append(label)
    print(f"  ✓ {label}")


def wait_for(predicate, timeout=10.0, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(interval)
    return None


def webhook_values(kind):
    with LOCK:
        items = list(RECEIVED)
    values = []
    for item in items:
        for entry in item["body"]["entry"]:
            for change in entry["changes"]:
                if kind in change["value"]:
                    values.append((item, change))
    return values


def find_message_hook(wamid):
    for item, change in webhook_values("messages"):
        for message in change["value"]["messages"]:
            if message["id"] == wamid:
                return item, change, message
    return None


def statuses_for(wamid):
    return [s["status"] for _, change in webhook_values("statuses") for s in change["value"]["statuses"] if s["id"] == wamid]


def status_object(wamid, status):
    for _, change in webhook_values("statuses"):
        for s in change["value"]["statuses"]:
            if s["id"] == wamid and s["status"] == status:
                return s
    return None


def send(client, to, message_type, content):
    return client.graph("POST", f"/{PHONE}/messages", {
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": to,
        "type": message_type,
        message_type: content,
    })


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://localhost:4000")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Receiver)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    client = Client(args.base)

    print("setup")
    client.control("PUT", "/chaos", {"preset": "off"})
    status, _ = client.control("POST", "/reset")
    check("reset", status == 200)
    status, snapshot = client.control("POST", "/seed", {
        "app": {"app_id": APP_ID, "app_secret": SECRET, "verify_token": VERIFY,
                "webhook_url": f"http://127.0.0.1:{args.port}/api/webhook/whatsapp"},
        "wabas": [{"id": WABA, "name": "Pizzaria Smoke", "subscribed": True,
                   "phone_numbers": [{"id": PHONE, "display_phone_number": "+55 11 4000-1234",
                                      "verified_name": "Pizzaria Smoke", "throughput_mps": 80}]}],
        "tokens": [{"token": TOKEN, "wabas": [WABA]}],
        "contacts": [{"wa_id": CUSTOMER, "profile_name": "Ana Cliente", "online": True, "read_policy": "on_open"}],
        "settings": {"sent_delay_ms": 100, "delivered_delay_ms": 200, "template_approval_policy": "manual"},
    })
    check("seed", status == 200 and snapshot["app"]["app_id"] == APP_ID, snapshot)
    status, verify = client.control("POST", "/webhooks/verify")
    check("webhook verify handshake (hub.challenge)", status == 200 and verify["ok"], verify)

    print("account endpoints (manual connection mode)")
    status, body = client.graph("GET", f"/{WABA}", query={"fields": "id"})
    check("GET /{waba}?fields=id → {id}", status == 200 and body == {"id": WABA}, body)
    status, body = client.call("GET", f"/v25.0/{WABA}/phone_numbers",
                               query={"fields": "id,display_phone_number,verified_name,quality_rating", "access_token": TOKEN})
    check("GET /{waba}/phone_numbers with access_token query", status == 200 and body["data"][0]["id"] == PHONE, body)
    status, body = client.graph("POST", f"/{WABA}/subscribed_apps")
    check("POST subscribed_apps → success", status == 200 and body == {"success": True}, body)
    status, body = client.call("GET", f"/v25.0/{WABA}", headers={"Authorization": "Bearer EAAinvalid"})
    check("invalid token → 401 code 190", status == 401 and body["error"]["code"] == 190, body)
    status, body = client.graph("POST", "/999999999999999/messages", {"messaging_product": "whatsapp"})
    check("unknown phone id → 400 code 100 subcode 33", status == 400 and body["error"].get("error_subcode") == 33, body)

    print("order bot flow")
    status, inbound = client.control("POST", f"/contacts/{CUSTOMER}/messages", {"type": "text", "text": "oi, quero pedir", "phone_number_id": PHONE})
    check("customer sends text", status == 201, inbound)
    hook = wait_for(lambda: find_message_hook(inbound["wamid"]))
    check("messages webhook delivered", hook is not None)
    item, change, message = hook
    check("webhook signature valid", item["sig_ok"])
    check("user-agent facebookexternalua", item["ua"] == "facebookexternalua", item["ua"])
    check("envelope object/entry/changes/field", item["body"]["object"] == "whatsapp_business_account" and change["field"] == "messages")
    check("metadata phone_number_id + digits display", change["value"]["metadata"] == {"display_phone_number": "551140001234", "phone_number_id": PHONE}, change["value"]["metadata"])
    check("contacts profile + wa_id", change["value"]["contacts"] == [{"profile": {"name": "Ana Cliente"}, "wa_id": CUSTOMER}], change["value"]["contacts"])
    check("message from/type/text/timestamp", message["from"] == CUSTOMER and message["text"] == {"body": "oi, quero pedir"} and message["timestamp"].isdigit(), message)

    status, body = client.graph("POST", f"/{PHONE}/messages", {"messaging_product": "whatsapp", "status": "read",
                                                                "message_id": inbound["wamid"], "typing_indicator": {"type": "text"}})
    check("read receipt + typing → success", status == 200 and body == {"success": True}, body)

    status, body = send(client, CUSTOMER, "interactive", {
        "type": "list", "body": {"text": "Qual pizza?"},
        "action": {"button": "Cardápio", "sections": [{"title": "Pizzas", "rows": [
            {"id": "calabresa", "title": "Calabresa", "description": "R$ 45"}]}]}})
    check("send list → 200 with contacts/messages", status == 200 and body["messages"][0]["id"].startswith("wamid.")
          and body["contacts"] == [{"input": CUSTOMER, "wa_id": CUSTOMER}] and "message_status" not in body["messages"][0], body)
    list_wamid = body["messages"][0]["id"]

    status, reply = client.control("POST", f"/contacts/{CUSTOMER}/reply-interactive", {"wamid": list_wamid, "id": "calabresa"})
    check("customer taps list row", status == 201, reply)
    hook = wait_for(lambda: find_message_hook(reply["wamid"]))
    check("list_reply webhook", hook is not None)
    _, _, message = hook
    check("list_reply shape + context", message["interactive"] == {"type": "list_reply", "list_reply": {"id": "calabresa", "title": "Calabresa", "description": "R$ 45"}}
          and message["context"] == {"from": "551140001234", "id": list_wamid}, message)

    order = {
        "type": "order_details", "body": {"text": "Seu pedido #123"},
        "action": {"name": "review_and_pay", "parameters": {
            "reference_id": "order-123", "type": "physical-goods", "payment_type": "br", "currency": "BRL",
            "total_amount": {"value": 5000, "offset": 100},
            "order": {"status": "pending",
                      "items": [{"name": "Calabresa", "amount": {"value": 4500, "offset": 100}, "quantity": 1, "retailer_id": "p1"}],
                      "subtotal": {"value": 4500, "offset": 100},
                      "tax": {"value": 500, "offset": 100, "description": "Taxa de entrega"}},
            "payment_settings": [{"type": "pix_dynamic_code", "pix_dynamic_code": {
                "code": "00020126580014br.gov.bcb.pix", "merchant_name": "Pizzaria", "key": "12345678000195", "key_type": "CNPJ"}}]}}}
    status, body = send(client, CUSTOMER, "interactive", order)
    check("send order_details (Pix) → 200", status == 200, body)
    order_wamid = body["messages"][0]["id"]

    bad = json.loads(json.dumps(order))
    bad["action"]["parameters"]["total_amount"]["value"] = 4999
    status, body = send(client, CUSTOMER, "interactive", bad)
    check("order_details with wrong total → 400 code 100", status == 400 and body["error"]["code"] == 100, body)

    wait_for(lambda: "delivered" in statuses_for(order_wamid))
    check("status sent → delivered webhooks", statuses_for(order_wamid)[:2] == ["sent", "delivered"], statuses_for(order_wamid))
    sent = status_object(order_wamid, "sent")
    check("status shape (recipient_id, timestamp, pricing PMP, no conversation)",
          sent["recipient_id"] == CUSTOMER and sent["timestamp"].isdigit() and sent["pricing"]["pricing_model"] == "PMP"
          and "conversation" not in sent, sent)

    conversation_id = reply["conversation_id"]
    status, _ = client.control("POST", f"/conversations/{conversation_id}/open")
    check("customer opens chat", status == 200)
    wait_for(lambda: "read" in statuses_for(order_wamid))
    check("read status webhook", "read" in statuses_for(order_wamid), statuses_for(order_wamid))

    status, wait_body = client.control("POST", "/wait", {"kind": "outbound_message", "contact": CUSTOMER, "timeout_ms": 200})
    check("wait times out with 408 when nothing new", status == 408, wait_body)

    print("window rules")
    client.control("POST", f"/conversations/{conversation_id}/expire-window")
    status, body = send(client, CUSTOMER, "text", {"preview_url": False, "body": "fora da janela"})
    check("text outside window → 200 accepted", status == 200, body)
    late = body["messages"][0]["id"]
    wait_for(lambda: "failed" in statuses_for(late))
    failed = status_object(late, "failed")
    check("failed webhook with 131047", failed is not None and failed["errors"][0]["code"] == 131047 and failed["errors"][0]["title"] == "Re-engagement message", failed)

    print("media")
    status, body = client.control("POST", f"/contacts/{CUSTOMER}/messages", {"type": "audio", "media_base64": "T2dnUw==", "mime_type": "audio/ogg; codecs=opus", "phone_number_id": PHONE})
    check("customer sends voice note", status == 201, body)
    hook = wait_for(lambda: find_message_hook(body["wamid"]))
    audio = hook[2]["audio"]
    check("audio webhook has id/sha256/url/voice", audio["voice"] is True and audio["url"].endswith("/_media/" + audio["id"]), audio)
    status, media = client.graph("GET", "/" + audio["id"])
    check("GET /{media_id}", status == 200 and media["mime_type"] == "audio/ogg; codecs=opus" and media["file_size"] == 4, media)
    download_path = urllib.parse.urlparse(media["url"]).path
    status, binary = client.call("GET", download_path, headers={"Authorization": "Bearer " + TOKEN})
    check("download media with bearer", status == 200 and binary in (b"OggS", "OggS"), binary)

    status, session = client.call("POST", f"/v25.0/{APP_ID}/uploads",
                                  query={"file_name": "promo.jpg", "file_length": 6, "file_type": "image/jpeg", "access_token": TOKEN}, raw=b"")
    check("resumable upload session", status == 200 and session["id"].startswith("upload:"), session)
    status, uploaded = client.call("POST", "/v25.0/" + session["id"], raw=bytes([255, 216, 255, 224, 0, 16]),
                                   headers={"Authorization": "OAuth " + TOKEN, "file_offset": "0",
                                            "content-type": "application/x-www-form-urlencoded"})
    check("resumable upload chunk (binary as urlencoded, like curl) → h", status == 200 and "h" in uploaded, uploaded)

    print("campaign flow")
    template = {"name": "crm_campaign_message", "language": "pt_BR", "category": "MARKETING", "components": [
        {"type": "HEADER", "format": "IMAGE", "example": {"header_handle": [uploaded["h"]]}},
        {"type": "BODY", "text": "Mensagem de *{{1}}*:\n\n{{2}}\n\n_Enviado via Loja_", "example": {"body_text": [["Pizzaria", "Promo"]]}}]}
    status, created = client.graph("POST", f"/{WABA}/message_templates", template)
    check("create template → PENDING", status == 200 and created["status"] == "PENDING", created)
    status, dup = client.graph("POST", f"/{WABA}/message_templates", template)
    check("duplicate template → 2388024", status == 400 and dup["error"].get("error_subcode") == 2388024, dup)
    status, listing = client.graph("GET", f"/{WABA}/message_templates", query={"fields": "name,status,category,language,components", "limit": 100})
    check("list templates shows PENDING", status == 200 and listing["data"][0]["status"] == "PENDING", listing)

    template_message = {"name": "crm_campaign_message", "language": {"code": "pt_BR"}, "components": [
        {"type": "header", "parameters": [{"type": "image", "image": {"link": "https://example.com/promo.jpg"}}]},
        {"type": "body", "parameters": [{"type": "text", "text": "Pizzaria"}, {"type": "text", "text": "50% off"}]}]}
    status, body = send(client, CUSTOMER, "template", template_message)
    check("send pending template → 404 code 132001", status == 404 and body["error"]["code"] == 132001, body)

    status, _ = client.control("POST", f"/templates/{created['id']}/approve")
    check("approve template via control API", status == 200)

    status, body = client.control("POST", "/contacts/bulk", {"count": 120})
    check("bulk contacts", status == 201, body)
    status, contacts = client.control("GET", "/contacts")
    numbers = [c["wa_id"] for c in contacts if c["wa_id"] != CUSTOMER][:120]

    # 50 msg/s during the burst: 120 sends span at most two 1 s windows, so at
    # most 100 can pass and 130429 is guaranteed regardless of window alignment.
    client.control("POST", "/seed", {"wabas": [{"id": WABA, "name": "Pizzaria Smoke", "phone_numbers": [
        {"id": PHONE, "display_phone_number": "+55 11 4000-1234", "verified_name": "Pizzaria Smoke", "throughput_mps": 50}]}]})

    results = []
    lock = threading.Lock()

    def fire(number):
        result = send(client, number, "template", template_message)
        with lock:
            results.append(result)

    started = time.time()
    threads = [threading.Thread(target=fire, args=(n,)) for n in numbers]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    elapsed = time.time() - started
    ok = [b for s, b in results if s == 200]
    limited = [b for s, b in results if s == 400 and b["error"]["code"] == 130429]
    other = [(s, b) for s, b in results if s != 200 and not (s == 400 and b["error"]["code"] == 130429)]
    print(f"    {len(numbers)} sends in {elapsed:.2f}s → {len(ok)} accepted, {len(limited)} rate limited (130429)")
    check("template sends return message_status accepted", all(b["messages"][0].get("message_status") == "accepted" for b in ok), ok[:1])
    check("no unexpected send errors", other == [], other[:3])
    if elapsed < 1.0:
        check("burst above the number's throughput gets 130429", len(limited) >= 20, len(limited))
    client.control("POST", "/seed", {"wabas": [{"id": WABA, "name": "Pizzaria Smoke", "phone_numbers": [
        {"id": PHONE, "display_phone_number": "+55 11 4000-1234", "verified_name": "Pizzaria Smoke", "throughput_mps": 80}]}]})

    accepted = [b["messages"][0]["id"] for b in ok]
    wait_for(lambda: all("delivered" in statuses_for(w) for w in accepted), timeout=30)
    delivered = sum(1 for w in accepted if "delivered" in statuses_for(w))
    check(f"all {len(accepted)} campaign messages delivered via webhook", delivered == len(accepted), delivered)
    status, logs = client.control("GET", "/requests", query={"limit": 5})
    check("graph requests logged with masked token", status == 200 and TOKEN not in json.dumps(logs), logs[:1])

    print("chaos")
    client.control("PUT", "/chaos", {"duplicate_rate": 1.0})
    status, body = client.control("POST", f"/contacts/{CUSTOMER}/messages", {"type": "text", "text": "duplicado?", "phone_number_id": PHONE})
    wait_for(lambda: len([1 for _, c in webhook_values("messages") for m in c["value"]["messages"] if m["id"] == body["wamid"]]) >= 2)
    copies = len([1 for _, c in webhook_values("messages") for m in c["value"]["messages"] if m["id"] == body["wamid"]])
    check("duplicate chaos delivers the same wamid twice", copies == 2, copies)
    client.control("PUT", "/chaos", {"preset": "off"})

    print(f"\nall {len(PASSED)} checks passed")
    server.shutdown()


if __name__ == "__main__":
    main()
