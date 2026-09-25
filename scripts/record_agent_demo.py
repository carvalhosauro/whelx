#!/usr/bin/env python3
"""
Records docs/assets/agent-demo.gif: a coding agent plays a customer through
whelx's MCP server and walks into the example sales bot's deliberate bug.

Every step is a real MCP `tools/call` against /_whelx/mcp (the same calls
Claude Code makes); the caption bar on each frame shows that call.

Prerequisites (on a FRESH whelx; this script does not reset it):
    curl -X POST $BASE/_whelx/seed -H 'content-type: application/json' -d @examples/sales-bot/seed.json
    GRAPH_API_BASE_URL=$BASE python3 examples/sales-bot/bot.py

Usage:
    python3 scripts/record_agent_demo.py --base http://localhost:4100
"""

import argparse
import json
import os
import tempfile
import time
import urllib.request

from PIL import Image, ImageDraw, ImageFont

from record_demo import default_chrome, shoot

CUSTOMER = "15550002222"
PHONE = "300000000000001"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def mcp(base, name, **args):
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": args}}
    request = urllib.request.Request(base + "/_whelx/mcp", data=json.dumps(body).encode(), headers={"content-type": "application/json"})
    result = json.loads(urllib.request.urlopen(request, timeout=60).read())["result"]
    if result["isError"]:
        raise RuntimeError(result["content"][0]["text"])
    return json.loads(result["content"][0]["text"])


def caption(path, title, line, width):
    image = Image.open(path).convert("RGB")
    bar_height = 64
    canvas = Image.new("RGB", (image.width, image.height + bar_height), (17, 24, 39))
    canvas.paste(image, (0, bar_height))
    draw = ImageDraw.Draw(canvas)
    bold = ImageFont.truetype(FONT_BOLD, 17) if os.path.exists(FONT_BOLD) else ImageFont.load_default()
    mono = ImageFont.truetype(FONT, 15) if os.path.exists(FONT) else ImageFont.load_default()
    draw.text((20, 10), title, fill=(167, 243, 208), font=bold)
    draw.text((20, 36), line, fill=(229, 231, 235), font=mono)
    canvas.save(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://localhost:4100")
    parser.add_argument("--chrome", default=default_chrome())
    parser.add_argument("--out", default="docs/assets/agent-demo.gif")
    parser.add_argument("--width", type=int, default=1200)
    parser.add_argument("--height", type=int, default=660)
    args = parser.parse_args()
    base = args.base.rstrip("/")
    chat = f"{base}/?phone={PHONE}&contact={CUSTOMER}"
    tmp = tempfile.mkdtemp(prefix="whelx-agent-demo-")
    frames = []

    def frame(title, line, duration):
        time.sleep(0.8)
        path = os.path.join(tmp, f"{len(frames):02d}.png")
        shoot(args.chrome, chat, path, args.width, args.height)
        caption(path, title, line, args.width)
        frames.append((path, duration))

    def wait(after):
        mcp(base, "wait_for", kind="outbound_message", contact=CUSTOMER, after=after, timeout_ms=10000)
        time.sleep(0.5)
        return mcp(base, "list_messages", contact=CUSTOMER, direction="outbound", limit=1)[0]["wamid"]

    agent = "Claude (via whelx MCP) · playing Daniel, a customer who asks a question mid-order"

    msg = mcp(base, "send_as_contact", wa_id=CUSTOMER, type="text", text="hey, what pizzas do you have?")
    last = wait(msg["wamid"])
    frame(agent, 'send_as_contact(type="text", text="hey, what pizzas do you have?")  →  wait_for(outbound_message)', 1800)

    msg = mcp(base, "reply_interactive", wa_id=CUSTOMER, wamid=last, id="four_cheese")
    last = wait(msg["wamid"])
    frame(agent, 'reply_interactive(id="four_cheese")  →  wait_for(outbound_message)', 1600)

    msg = mcp(base, "reply_interactive", wa_id=CUSTOMER, wamid=last, id="no_drink")
    wait(msg["wamid"])
    frame(agent, 'reply_interactive(id="no_drink")  →  wait_for(outbound_message)', 1600)

    msg = mcp(base, "send_as_contact", wa_id=CUSTOMER, type="text", text="is delivery free?")
    wait(msg["wamid"])
    frame(agent, 'send_as_contact(type="text", text="is delivery free?")  →  wait_for(outbound_message)', 1800)

    frame("Claude: found it. A question mid-funnel restarts the chat and empties the cart.",
          "bot.py → handle(): kind == \"text\" outside new/done resets CARTS[customer]. Answer and resume instead.", 4200)

    images = [Image.open(path).convert("RGB") for path, _ in frames]
    palette = images[-2].quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    quantized = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in images]
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    quantized[0].save(args.out, save_all=True, append_images=quantized[1:], duration=[d for _, d in frames], loop=0, optimize=True)
    print(f"wrote {args.out} ({len(frames)} frames, {os.path.getsize(args.out) // 1024} KB)")


if __name__ == "__main__":
    main()
