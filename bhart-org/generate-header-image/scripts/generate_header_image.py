#!/usr/bin/env python
import argparse
import mimetypes
import os
import sys
import urllib.request
import uuid

from google import genai
from google.genai import types

DEFAULT_ASPECT_RATIO = "16:9"
DEFAULT_RESOLUTION = "1K"
DEFAULT_MODEL = "gemini-3-pro-image-preview"


def save_binary_file(file_name, data):
    with open(file_name, "wb") as f:
        f.write(data)


def load_image_from_path(path):
    if not os.path.exists(path):
        raise SystemExit(f"Reference image not found: {path}")
    mime_type, _ = mimetypes.guess_type(path)
    with open(path, "rb") as f:
        data = f.read()
    return types.Part.from_bytes(
        data=data,
        mime_type=mime_type or "image/jpeg",
    )


def load_image_from_url(url):
    request = urllib.request.Request(url, headers={"User-Agent": "codex"})
    with urllib.request.urlopen(request) as response:
        data = response.read()
        content_type = response.headers.get("Content-Type", "").split(";")[0].strip()
    mime_type = content_type or mimetypes.guess_type(url)[0] or "image/jpeg"
    return types.Part.from_bytes(
        data=data,
        mime_type=mime_type,
    )


def generate_image(prompt: str, model: str, aspect_ratio: str, resolution: str, reference_paths, reference_urls):
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise SystemExit("Missing required env var: GEMINI_API_KEY")

    client = genai.Client(api_key=api_key)

    image_parts = []
    for path in reference_paths:
        image_parts.append(load_image_from_path(path))
    for url in reference_urls:
        image_parts.append(load_image_from_url(url))

    contents = [
        types.Content(
            role="user",
            parts=[
                types.Part.from_text(text=prompt),
                *image_parts,
            ],
        )
    ]

    generate_content_config = types.GenerateContentConfig(
        response_modalities=["IMAGE", "TEXT"],
        image_config=types.ImageConfig(
            aspect_ratio=aspect_ratio,
            image_size=resolution,
        ),
    )

    response_stream = client.models.generate_content_stream(
        model=model,
        contents=contents,
        config=generate_content_config,
    )

    for chunk in response_stream:
        if not chunk.candidates:
            continue
        content = chunk.candidates[0].content
        if not content or not content.parts:
            continue
        for part in content.parts:
            if getattr(part, "thought", False):
                continue
            inline = part.inline_data
            if inline and inline.data:
                file_base = f"/tmp/header-image-{uuid.uuid4().hex}"
                file_extension = mimetypes.guess_extension(inline.mime_type or "image/png") or ".png"
                file_path = f"{file_base}{file_extension}"
                save_binary_file(file_path, inline.data)
                print(file_path)
                return file_path

    raise SystemExit("No image data was returned by the model.")


def main():
    parser = argparse.ArgumentParser(description="Generate a blog header image using Gemini.")
    parser.add_argument("--prompt", required=True, help="Image prompt text.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Gemini model name.")
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

    args = parser.parse_args()

    try:
        generate_image(
            prompt=args.prompt,
            model=args.model,
            aspect_ratio=args.aspect_ratio,
            resolution=args.resolution,
            reference_paths=args.reference_file,
            reference_urls=args.reference_url,
        )
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
