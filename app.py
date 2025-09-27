"""Flask application that bridges WeChat messages to ChatGPT responses."""
import hashlib
import os
import time
from dataclasses import dataclass
from xml.etree import ElementTree as ET

from flask import Flask, abort, request, Response

try:
    from openai import OpenAI
except ImportError as exc:  # pragma: no cover - imported at runtime
    raise RuntimeError(
        "The `openai` package is required. Install dependencies first."
    ) from exc


@dataclass
class WeChatMessage:
    """Representation of the minimal subset of a WeChat XML message we care about."""

    to_user: str
    from_user: str
    msg_type: str
    content: str | None = None

    @classmethod
    def from_xml(cls, xml_payload: str) -> "WeChatMessage":
        """Parse the incoming XML payload from WeChat into a ``WeChatMessage``."""
        try:
            root = ET.fromstring(xml_payload)
        except ET.ParseError as exc:  # pragma: no cover - WeChat always sends valid XML
            raise ValueError("Invalid XML payload received from WeChat") from exc

        data: dict[str, str] = {child.tag: (child.text or "") for child in root}
        return cls(
            to_user=data.get("ToUserName", ""),
            from_user=data.get("FromUserName", ""),
            msg_type=data.get("MsgType", ""),
            content=data.get("Content"),
        )

    def build_text_response(self, reply: str) -> str:
        """Build the XML response to send back to WeChat."""
        timestamp = int(time.time())
        return (
            "<xml>"
            f"<ToUserName><![CDATA[{self.from_user}]]></ToUserName>"
            f"<FromUserName><![CDATA[{self.to_user}]]></FromUserName>"
            f"<CreateTime>{timestamp}</CreateTime>"
            "<MsgType><![CDATA[text]]></MsgType>"
            f"<Content><![CDATA[{reply}]]></Content>"
            "</xml>"
        )


def verify_wechat_request(*, token: str, signature: str, timestamp: str, nonce: str) -> bool:
    """Verify that the request really comes from the WeChat server."""
    to_hash = "".join(sorted([token, timestamp, nonce]))
    expected_signature = hashlib.sha1(to_hash.encode("utf-8")).hexdigest()
    return expected_signature == signature


def build_chatgpt_reply(content: str) -> str:
    """Send the incoming message content to ChatGPT and return its reply."""
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY must be configured")

    client = OpenAI(api_key=api_key)
    model = os.environ.get("OPENAI_MODEL", "gpt-3.5-turbo")
    completion = client.chat.completions.create(
        model=model,
        messages=[
            {
                "role": "system",
                "content": "You are a helpful assistant responding to messages from WeChat users.",
            },
            {"role": "user", "content": content},
        ],
    )
    return completion.choices[0].message.content.strip()


app = Flask(__name__)


@app.route("/wechat", methods=["GET", "POST"])
def wechat_handler() -> Response:
    token = os.environ.get("WECHAT_TOKEN")
    if not token:
        raise RuntimeError("WECHAT_TOKEN must be configured")

    signature = request.args.get("signature", "")
    timestamp = request.args.get("timestamp", "")
    nonce = request.args.get("nonce", "")

    if not verify_wechat_request(
        token=token, signature=signature, timestamp=timestamp, nonce=nonce
    ):
        abort(403)

    if request.method == "GET":
        echostr = request.args.get("echostr", "")
        return Response(echostr)

    raw_xml = request.data.decode("utf-8")
    message = WeChatMessage.from_xml(raw_xml)

    if message.msg_type != "text" or not message.content:
        # Only text messages are supported right now. WeChat requires an empty
        # response for unsupported message types to acknowledge receipt.
        return Response("success")

    reply_content = build_chatgpt_reply(message.content)
    response_xml = message.build_text_response(reply_content)
    return Response(response_xml, mimetype="application/xml")


if __name__ == "__main__":  # pragma: no cover - manual run helper
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8000)), debug=True)
