#!/usr/bin/env python3
"""
Luigi's Pizza: a tiny WhatsApp sales bot to try whelx with.

It is a plain WhatsApp Cloud API app: it receives signed webhooks and answers
through the Graph API. The only whelx-specific thing is GRAPH_API_BASE_URL.

Funnel: greeting → pizza menu (list) → upsell (buttons) → confirmation
(buttons) → Pix order (order_details).

It ships with ONE deliberate bug so your coding agent has something to find.
Look for "DELIBERATE BUG" below, but try the agent first.

Standard library only:
    python3 examples/sales-bot/bot.py
"""

import hashlib
import hmac
import json
import os
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GRAPH = os.environ.get("GRAPH_API_BASE_URL", "http://localhost:4000").rstrip("/")
VERSION = os.environ.get("GRAPH_API_VERSION", "v25.0")
TOKEN = os.environ.get("WHATSAPP_ACCESS_TOKEN", "EAAsalesbotdemotoken")
PHONE_ID = os.environ.get("WHATSAPP_PHONE_NUMBER_ID", "300000000000001")
APP_SECRET = os.environ.get("META_APP_SECRET", "0123456789abcdef0123456789abcdef")
VERIFY_TOKEN = os.environ.get("WEBHOOK_VERIFY_TOKEN", "sales-bot-verify")
PORT = int(os.environ.get("PORT", "8801"))

PIZZAS = {
    "margherita": ("Margherita", 4900),
    "pepperoni": ("Pepperoni", 5900),
    "four_cheese": ("Four cheese", 6200),
}
DRINK = ("Coke 2L", 1200)
DELIVERY = 500

# One cart per customer: {"pizza": id, "drink": bool, "step": str}
CARTS = {}
LOCK = threading.Lock()


def graph(payload):
    request = urllib.request.Request(
        f"{GRAPH}/{VERSION}/{PHONE_ID}/messages",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        print(f"graph error {error.code}: {error.read().decode()}")
        return None


def send(to, message_type, content):
    return graph({"messaging_product": "whatsapp", "recipient_type": "individual", "to": to, "type": message_type, message_type: content})


def text(to, body):
    send(to, "text", {"body": body})


def buttons(to, body, options):
    send(to, "interactive", {"type": "button", "body": {"text": body}, "action": {
        "buttons": [{"type": "reply", "reply": {"id": key, "title": title}} for key, title in options]}})


def menu(to):
    rows = [{"id": key, "title": name, "description": f"R$ {price / 100:.2f}".replace(".", ",")} for key, (name, price) in PIZZAS.items()]
    send(to, "interactive", {"type": "list", "header": {"type": "text", "text": "Luigi's menu"},
                             "body": {"text": "What are you craving tonight?"},
                             "action": {"button": "See pizzas", "sections": [{"title": "Pizzas", "rows": rows}]}})


def order(to, cart):
    name, price = PIZZAS[cart["pizza"]]
    items = [{"retailer_id": cart["pizza"], "name": f"{name} pizza", "amount": {"value": price, "offset": 100}, "quantity": 1}]
    if cart["drink"]:
        items.append({"retailer_id": "coke", "name": DRINK[0], "amount": {"value": DRINK[1], "offset": 100}, "quantity": 1})
    subtotal = sum(i["amount"]["value"] for i in items)
    send(to, "interactive", {"type": "order_details", "body": {"text": "Here's your order. Pay with Pix and we start baking."},
                             "action": {"name": "review_and_pay", "parameters": {
                                 "reference_id": f"{abs(hash(to)) % 10000}", "type": "physical-goods", "payment_type": "br", "currency": "BRL",
                                 "total_amount": {"value": subtotal + DELIVERY, "offset": 100},
                                 "order": {"status": "pending", "items": items,
                                           "subtotal": {"value": subtotal, "offset": 100},
                                           "shipping": {"value": DELIVERY, "offset": 100, "description": "Delivery"}},
                                 "payment_settings": [{"type": "pix_dynamic_code", "pix_dynamic_code": {
                                     "code": "00020126580014br.gov.bcb.pix0136luigi", "merchant_name": "Luigi's Pizza",
                                     "key": "12345678000195", "key_type": "CNPJ"}}]}}})


def handle(message, name):
    customer = message["from"]
    kind = message["type"]
    reply_id = None
    if kind == "interactive":
        reply = message["interactive"].get("list_reply") or message["interactive"].get("button_reply") or {}
        reply_id = reply.get("id")

    # Read receipt + typing indicator, like a real bot.
    graph({"messaging_product": "whatsapp", "status": "read", "message_id": message["id"], "typing_indicator": {"type": "text"}})

    with LOCK:
        cart = CARTS.setdefault(customer, {"pizza": None, "drink": False, "step": "new"})

        if reply_id in PIZZAS:
            cart.update(pizza=reply_id, step="upsell")
            buttons(customer, f"Great choice! Add a {DRINK[0]} for R$ 12,00?", [("add_drink", "Yes, add it"), ("no_drink", "No thanks")])
        elif reply_id in ("add_drink", "no_drink") and cart["pizza"]:
            cart.update(drink=reply_id == "add_drink", step="confirm")
            summary = PIZZAS[cart["pizza"]][0] + (f" + {DRINK[0]}" if cart["drink"] else "")
            buttons(customer, f"{summary}, delivered in 30 min. Place the order?", [("place", "Place order"), ("change", "Change pizza")])
        elif reply_id == "place" and cart["pizza"]:
            cart["step"] = "paying"
            order(customer, cart)
        elif reply_id == "change":
            cart.update(pizza=None, drink=False, step="menu")
            menu(customer)
        elif kind == "text" and cart["step"] in ("new", "done"):
            cart["step"] = "menu"
            text(customer, f"Hi {name.split()[0]}! Welcome to Luigi's 🍕")
            menu(customer)
        elif kind == "text":
            # DELIBERATE BUG: a question typed mid-funnel ("is delivery free?")
            # restarts the conversation and silently empties the cart, instead
            # of answering and resuming where the customer was.
            CARTS[customer] = {"pizza": None, "drink": False, "step": "menu"}
            text(customer, "Sorry, I didn't get that. Let's start over!")
            menu(customer)
        else:
            text(customer, "Tap one of the options above 🙂")


class Webhook(BaseHTTPRequestHandler):
    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if query.get("hub.mode") == ["subscribe"] and query.get("hub.verify_token") == [VERIFY_TOKEN]:
            self._reply(200, query["hub.challenge"][0])
        else:
            self._reply(403, "forbidden")

    def do_POST(self):
        body = self.rfile.read(int(self.headers["content-length"]))
        expected = "sha256=" + hmac.new(APP_SECRET.encode(), body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(self.headers.get("x-hub-signature-256", ""), expected):
            return self._reply(403, "bad signature")

        self._reply(200, "OK")  # acknowledge first, like production bots should
        payload = json.loads(body)
        for entry in payload.get("entry", []):
            for change in entry.get("changes", []):
                value = change.get("value", {})
                names = {c["wa_id"]: c["profile"]["name"] for c in value.get("contacts", [])}
                for message in value.get("messages", []):
                    handle(message, names.get(message["from"], "there"))

    def _reply(self, status, text_body):
        data = text_body.encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"Luigi's Pizza bot on :{PORT} → Graph API at {GRAPH}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Webhook).serve_forever()
