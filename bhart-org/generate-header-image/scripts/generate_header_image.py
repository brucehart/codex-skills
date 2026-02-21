#!/usr/bin/env python3
import argparse
import base64
import json
import mimetypes
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

API_BASE = "https://api.replicate.com/v1"
DEFAULT_MODEL = "google/nano-banana-pro"
FALLBACK_MODEL = "black-forest-labs/flux-1.1-pro"
DEFAULT_ASPECT_RATIO = "16:9"
DEFAULT_RESOLUTION = "2K"
DEFAULT_POLL_SECONDS = 3


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required env var: {name}")
    return value


def read_poll_seconds() -> int:
    raw = os.environ.get("HEADER_IMAGE_POLL_SECONDS", "").strip()
    if not raw:
        return DEFAULT_POLL_SECONDS
    try:
        value = int(raw)
    except ValueError:
        log(f"Invalid HEADER_IMAGE_POLL_SECONDS: {raw} (using {DEFAULT_POLL_SECONDS})")
        return DEFAULT_POLL_SECONDS
    if value < 1:
        log(f"HEADER_IMAGE_POLL_SECONDS must be >= 1 (using {DEFAULT_POLL_SECONDS})")
        return DEFAULT_POLL_SECONDS
    return value


def to_data_uri_from_path(path: str) -> str:
    p = pathlib.Path(path)
    if not p.exists():
        raise SystemExit(f"Reference image not found: {path}")
    mime = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
    encoded = base64.b64encode(p.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def to_data_uri_from_url(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "codex"})
    with urllib.request.urlopen(request) as response:
        data = response.read()
        content_type = response.headers.get("Content-Type", "").split(";")[0].strip()
    mime = content_type or mimetypes.guess_type(url)[0] or "application/octet-stream"
    encoded = base64.b64encode(data).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def replicate_request(token: str, method: str, url: str, payload: dict | None = None) -> dict:
    headers = {
        "Authorization": f"Token {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url=url, method=method, headers=headers, data=data)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Replicate API error {exc.code}: {body[:2000]}") from exc


def wait_for_prediction(token: str, prediction_id: str) -> dict:
    poll_seconds = read_poll_seconds()
    url = f"{API_BASE}/predictions/{prediction_id}"
    while True:
        pred = replicate_request(token, "GET", url)
        status = pred.get("status")
        if status == "succeeded":
            return pred
        if status in {"failed", "canceled"}:
            err = pred.get("error") or "Prediction did not succeed."
            raise RuntimeError(f"Prediction {status}: {err}")
        log(f"Image not ready yet (status={status}). Checking again in {poll_seconds}s...")
        time.sleep(poll_seconds)


def first_output_url(output: object) -> str:
    if isinstance(output, str) and output:
        return output
    if isinstance(output, list):
        for item in output:
            if isinstance(item, str) and item:
                return item
    raise RuntimeError(f"Unexpected prediction output: {output!r}")


def guess_extension(url: str, headers: dict[str, str]) -> str:
    content_type = headers.get("Content-Type", "").split(";")[0].strip().lower()
    if content_type:
        ext = mimetypes.guess_extension(content_type)
        if ext:
            return ext
    parsed = urllib.parse.urlparse(url)
    suffix = pathlib.Path(parsed.path).suffix.lower()
    if suffix in {".jpg", ".jpeg", ".png", ".webp"}:
        return suffix
    return ".jpg"


def download_file(url: str, prefix: str, default_ext: str) -> str:
    req = urllib.request.Request(url=url, method="GET")
    with urllib.request.urlopen(req) as resp:
        data = resp.read()
        headers = {k: v for k, v in resp.headers.items()}
    ext = guess_extension(url, headers) or default_ext
    output_path = f"/tmp/{prefix}-{uuid.uuid4().hex}{ext}"
    with open(output_path, "wb") as f:
        f.write(data)
    return output_path


def run_prediction(token: str, model: str, payload: dict) -> tuple[str, str]:
    create_url = f"{API_BASE}/models/{model}/predictions"
    prediction = replicate_request(token, "POST", create_url, payload)
    prediction_id = prediction.get("id")
    if not prediction_id:
        raise RuntimeError(f"Missing prediction id from create response: {prediction}")
    final = wait_for_prediction(token, prediction_id)
    output_url = first_output_url(final.get("output"))
    local_path = download_file(output_url, "header-image", ".jpg")
    return local_path, output_url


def generate_image(
    prompt: str,
    model: str,
    aspect_ratio: str,
    resolution: str,
    reference_paths: list[str],
    reference_urls: list[str],
) -> tuple[str, str, str]:
    token = require_env("REPLICATE_API_TOKEN")

    image_input = [to_data_uri_from_path(path) for path in reference_paths]
    image_input.extend(to_data_uri_from_url(url) for url in reference_urls)

    primary_payload = {
        "input": {
            "prompt": prompt,
            "image_input": image_input,
            "aspect_ratio": aspect_ratio,
            "resolution": resolution,
            "output_format": "jpg",
            "safety_filter_level": "block_only_high",
        }
    }

    try:
        local_path, output_url = run_prediction(token, model, primary_payload)
        return local_path, output_url, model
    except Exception as primary_err:
        if model != DEFAULT_MODEL:
            raise
        log(f"Primary image model failed ({model}): {primary_err}")
        log(f"Falling back to {FALLBACK_MODEL}...")
        fallback_payload = {
            "input": {
                "prompt": prompt,
                "aspect_ratio": aspect_ratio,
                "output_format": "png",
            }
        }
        local_path, output_url = run_prediction(token, FALLBACK_MODEL, fallback_payload)
        return local_path, output_url, FALLBACK_MODEL


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a blog header image via Replicate.")
    parser.add_argument("--prompt", required=True, help="Image prompt text.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Replicate model slug.")
    parser.add_argument("--aspect-ratio", default=DEFAULT_ASPECT_RATIO, help="Aspect ratio for the image.")
    parser.add_argument("--resolution", default=DEFAULT_RESOLUTION, help="Image resolution.")
    parser.add_argument(
        "--reference-file",
        action="append",
        default=[],
        help="Path to a reference image (repeatable).",
    )
    parser.add_argument(
        "--reference-url",
        action="append",
        default=[],
        help="URL to a reference image (repeatable).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON metadata with path/model/output_url.",
    )
    args = parser.parse_args()

    try:
        path, output_url, used_model = generate_image(
            prompt=args.prompt,
            model=args.model,
            aspect_ratio=args.aspect_ratio,
            resolution=args.resolution,
            reference_paths=args.reference_file,
            reference_urls=args.reference_url,
        )
        if args.json:
            print(json.dumps({"path": path, "model": used_model, "output_url": output_url}))
        else:
            print(path)
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
