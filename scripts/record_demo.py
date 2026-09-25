#!/usr/bin/env python3
"""
Records docs/assets/demo.gif: a customer orders a pizza in the whelx chat.

Drives a *fresh* whelx instance through the control API and the Graph API
(playing both the customer and a bot), screenshots the chat page after each
step with headless Chromium, and assembles the frames into a GIF with Pillow.

Usage:
    python3 scripts/record_demo.py --base http://localhost:4100 [--chrome PATH] [--out docs/assets/demo.gif]

WARNING: resets the target instance. Never point it at an instance in use.
Requires: Pillow, a Chromium/Chrome binary (defaults to Playwright's headless shell).
"""

import argparse
import glob
import json
import os
import subprocess
import tempfile
import time
import urllib.request

from PIL import Image

WABA = "200000000000001"
PHONE = "300000000000001"
TOKEN = "EAAdemotoken0000001"
CUSTOMER = "15550001111"


def call(base, method, path, body=None, token=None):
    request = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None, method=method)
    request.add_header("content-type", "application/json")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read() or b"null")


def send(base, message_type, content):
    body = {"messaging_product": "whatsapp", "recipient_type": "individual", "to": CUSTOMER, "type": message_type, message_type: content}
    return call(base, "POST", f"/v25.0/{PHONE}/messages", body, TOKEN)["messages"][0]["id"]


def default_chrome():
    matches = sorted(glob.glob(os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell")))
    return matches[-1] if matches else "chromium"


def shoot(chrome, url, path, width, height):
    subprocess.run(
        [chrome, "--no-sandbox", "--disable-gpu", "--hide-scrollbars", f"--window-size={width},{height}",
         "--timeout=3500", f"--screenshot={path}", url],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60, check=False,
    )
    if not os.path.exists(path):
        raise RuntimeError(f"screenshot failed for {url}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://localhost:4100")
    parser.add_argument("--chrome", default=default_chrome())
    parser.add_argument("--out", default="docs/assets/demo.gif")
    parser.add_argument("--width", type=int, default=1200)
    parser.add_argument("--height", type=int, default=720)
    args = parser.parse_args()
    base = args.base.rstrip("/")

    call(base, "POST", "/_whelx/reset")
    call(base, "POST", "/_whelx/seed", {
        "app": {"webhook_url": None},
        "wabas": [{"id": WABA, "name": "Luigi's Pizza", "subscribed": True,
                   "phone_numbers": [{"id": PHONE, "display_phone_number": "+1 555 010 2030", "verified_name": "Luigi's Pizza"}]}],
        "tokens": [{"token": TOKEN, "wabas": [WABA]}],
        "contacts": [{"wa_id": CUSTOMER, "profile_name": "Maya Chen", "read_policy": "on_open"},
                     {"wa_id": "15550002222", "profile_name": "Daniel Ortiz"},
                     {"wa_id": "15550003333", "profile_name": "Priya Raman"}],
        "settings": {"sent_delay_ms": 50, "delivered_delay_ms": 50},
    })

    chat = f"{base}/?phone={PHONE}&contact={CUSTOMER}"
    frames = []
    tmp = tempfile.mkdtemp(prefix="whelx-demo-")

    def frame(duration_ms, settle=0.6):
        time.sleep(settle)
        path = os.path.join(tmp, f"{len(frames):02d}.png")
        shoot(args.chrome, chat, path, args.width, args.height)
        frames.append((path, duration_ms))

    frame(900)

    inbound = call(base, "POST", f"/_whelx/contacts/{CUSTOMER}/messages",
                   {"type": "text", "text": "Hi! Can I order a pizza? 🍕", "phone_number_id": PHONE})
    frame(1100)

    call(base, "POST", f"/v25.0/{PHONE}/messages",
         {"messaging_product": "whatsapp", "status": "read", "message_id": inbound["wamid"], "typing_indicator": {"type": "text"}}, TOKEN)
    frame(1100)

    menu = send(base, "interactive", {
        "type": "list", "header": {"type": "text", "text": "Luigi's menu"},
        "body": {"text": "Of course, Maya! What are you craving tonight?"},
        "action": {"button": "See pizzas", "sections": [{"title": "Pizzas", "rows": [
            {"id": "margherita", "title": "Margherita", "description": "Tomato, mozzarella, basil"},
            {"id": "pepperoni", "title": "Pepperoni", "description": "The classic, extra crispy"},
            {"id": "four_cheese", "title": "Four cheese", "description": "For cheese lovers"}]}]}})
    frame(1400)

    call(base, "POST", f"/_whelx/contacts/{CUSTOMER}/reply-interactive", {"wamid": menu, "id": "pepperoni"})
    frame(1000)

    confirm = send(base, "interactive", {
        "type": "button", "body": {"text": "Great choice! A large pepperoni, delivered in 30 min. Shall I place the order?"},
        "action": {"buttons": [{"type": "reply", "reply": {"id": "confirm", "title": "Yes, order it"}},
                               {"type": "reply", "reply": {"id": "change", "title": "Change"}}]}})
    frame(1400)

    call(base, "POST", f"/_whelx/contacts/{CUSTOMER}/reply-interactive", {"wamid": confirm, "id": "confirm"})
    frame(1000)

    send(base, "interactive", {
        "type": "order_details", "body": {"text": "Here's your order. Pay with Pix and we start baking 👨‍🍳"},
        "action": {"name": "review_and_pay", "parameters": {
            "reference_id": "1042", "type": "physical-goods", "payment_type": "br", "currency": "BRL",
            "total_amount": {"value": 6400, "offset": 100},
            "order": {"status": "pending",
                      "items": [{"retailer_id": "pepperoni-l", "name": "Large pepperoni", "amount": {"value": 5900, "offset": 100}, "quantity": 1}],
                      "subtotal": {"value": 5900, "offset": 100},
                      "shipping": {"value": 500, "offset": 100, "description": "Delivery"}},
            "payment_settings": [{"type": "pix_dynamic_code", "pix_dynamic_code": {
                "code": "00020126580014br.gov.bcb.pix0136demo", "merchant_name": "Luigi's Pizza", "key": "12345678000195", "key_type": "CNPJ"}}]}}})
    frame(3200, settle=1.5)

    images = [Image.open(path).convert("RGB") for path, _ in frames]
    durations = [duration for _, duration in frames]
    palette_source = images[-1].quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    quantized = [image.quantize(palette=palette_source, dither=Image.Dither.NONE) for image in images]
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    quantized[0].save(args.out, save_all=True, append_images=quantized[1:], duration=durations, loop=0, optimize=True)
    print(f"wrote {args.out} ({len(frames)} frames, {os.path.getsize(args.out) // 1024} KB)")


if __name__ == "__main__":
    main()
