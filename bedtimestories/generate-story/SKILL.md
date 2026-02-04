---
name: generate-story
description: Draft a new bedtime story.
metadata:
  short-description: Draft a new bedtime story.
---

# Generate Story (Codex)

You will be given:
- A story subject (prompt) for James.
- A folder path that may contain reference images and may include a date in the folder name.
- Optionally a markdown file name that may include a date.

Required environment variables:
- `GEMINI_API_KEY` for Google Vertex (Gemini).
- `STORY_API_TOKEN` for the worker automation API.
- `STORY_API_BASE_URL` (optional). If not set, use `https://bedtimestories.bruce-hart.workers.dev`.

Activate the Python venv for any steps that run Python:
```bash
source ~/scripts/.venv/bin/activate
```

Use the following workflow exactly.

## Step 0: Resolve story date
1) If the folder name contains a `YYYY-MM-DD` date, use that.
2) Else if the markdown file name contains a `YYYY-MM-DD` date, use that.
3) Else find the next date (including today) that does not already have a story:
   - Use the story API token to query existing story days.
   - Fetch a range starting today through today + 365 days (extend the range if needed).
   - Pick the earliest date in that range that is not present in the calendar data.

Example:
```bash
START=$(date -u +%Y-%m-%d)
END=$(date -u -d "+365 days" +%Y-%m-%d)
curl -s "https://bedtimestories.bruce-hart.workers.dev/api/stories/calendar?start=$START&end=$END" \
  -H "X-Story-Token: $STORY_API_TOKEN"
```
The response includes `{ "days": [ { "day": "YYYY-MM-DD", "count": N }, ... ] }`.
Choose the first date starting at `START` that is missing from the `days` list.

Helper script:
```bash
STORY_API_TOKEN=... \
STORY_API_BASE_URL=https://bedtimestories.bruce-hart.workers.dev \
/mnt/c/Users/admin/Documents/Code/bedtimestories/.codex/skills/generate-story/scripts/next-open-date.py
```
Environment variables:
- `STORY_API_TOKEN` (required): story automation API token.
- `STORY_API_BASE_URL` (optional): defaults to `https://bedtimestories.bruce-hart.workers.dev`.
- `STORY_CALENDAR_DAYS` (optional): number of days to scan per request (default 365).

## Step 1: Write the story text (Markdown)
Follow these instructions exactly:

For the given prompt, write a bedtime story including a title for my six year old son James. Make the text simple and phonics friendly for a beginning reader. Return the title separately and do not include it in the story content.

[Story Content]

In addition to Mom and Dad in his family, James has a three year old sister named Grace. He also has a small tuxedo cat named Trixie. In his family is also Granny and Grandpa Rick and Grandma and Grandpa Bruce. Only include people that are relevant to the story. Do not include people just to include them.

Do not use words in any image generated. Images should be in landscape format and have a cartoon aesthetic. Only include people in the images that are relevant to the scene of the story being visualized.

James has fair skin and short brown hair.

Mom has fair skin, shoulder length brown hair with blonde highlights and glasses.

Grace has long brown hair and fair skin.

Dad is bald and clean shaven with brown hair and thick dark eyebrows.

Granny is short with short gray hair.

Grandma has short blonde hair and glasses.

Grandpa is bald and clean shaven.

Trixie is a black cat with short legs, white paws, black chin, black face and a white chest.

Story format requirements:
- Plain text only (no Markdown).
- Do not include the title in the story content.
- Use short paragraphs separated by blank lines.
- Keep sentences short and easy to read.

## Step 2: Generate a cover image (Google Vertex Gemini)
Model: `gemini-3-pro-image-preview`

Image requirements:
- Landscape, 16:9.
- 1K resolution.
- Cartoon aesthetic.
- No text, letters, or signage.
- Only include characters relevant to the selected scene.
- Incorporate reference images as guidance when available (describe them in the prompt).

Install dependency:
```bash
pip install google-genai
```

Generate and save the image locally (example):
```bash
python - <<'PY'
import mimetypes
import os
from google import genai
from google.genai import types

def save_binary_file(file_name, data):
    with open(file_name, "wb") as f:
        f.write(data)
    print(f"File saved to: {file_name}")

def generate():
    client = genai.Client(
        api_key=os.environ.get("GEMINI_API_KEY"),
    )

    model = "gemini-3-pro-image-preview"
    contents = [
        types.Content(
            role="user",
            parts=[
                types.Part.from_text(
                    text="YOUR_IMAGE_PROMPT. 16:9 landscape, 1K resolution, cartoon style, no text."
                ),
            ],
        ),
    ]
    generate_content_config = types.GenerateContentConfig(
        response_modalities=[
            "IMAGE",
            "TEXT",
        ],
        image_config=types.ImageConfig(
            image_size="1K",
        ),
    )

    file_index = 0
    for chunk in client.models.generate_content_stream(
        model=model,
        contents=contents,
        config=generate_content_config,
    ):
        if (
            chunk.candidates is None
            or chunk.candidates[0].content is None
            or chunk.candidates[0].content.parts is None
        ):
            continue
        part = chunk.candidates[0].content.parts[0]
        if part.inline_data and part.inline_data.data:
            file_name = f"/tmp/story-image-{file_index}"
            file_index += 1
            inline_data = part.inline_data
            data_buffer = inline_data.data
            file_extension = mimetypes.guess_extension(inline_data.mime_type)
            save_binary_file(f"{file_name}{file_extension}", data_buffer)
        else:
            print(chunk.text)

if __name__ == "__main__":
    generate()
PY
```

Use the saved image file (e.g., `/tmp/story-image-0.jpg`) for upload.

## Step 3: Generate a short video (Google Vertex Veo)
Model: `veo-3.1-fast-generate-preview`

Video requirements:
- 16:9 landscape.
- 8 seconds.
- 24 fps.
- Cartoon aesthetic.
- No text or letters.
- Use the story to build a concise scene prompt.

Install dependency:
```bash
pip install google-genai pillow
```

Generate and save the video locally (example):
```bash
python - <<'PY'
import time
import os
from google import genai
from google.genai import types

MODEL = "veo-3.1-fast-generate-preview"

client = genai.Client(
    http_options={"api_version": "v1beta"},
    api_key=os.environ.get("GEMINI_API_KEY"),
)

video_config = types.GenerateVideosConfig(
    aspect_ratio="16:9",
    number_of_videos=1,
    duration_seconds=8,
    frame_rate=24,
    person_generation="ALLOW_ALL",
    resolution="720p",
)

def generate():
    operation = client.models.generate_videos(
        model=MODEL,
        prompt="YOUR_VIDEO_PROMPT. 16:9 landscape, 8s, 24 fps, cartoon style, no text.",
        config=video_config,
    )

    while not operation.done:
        print("Video has not been generated yet. Check again in 10 seconds...")
        time.sleep(10)
        operation = client.operations.get(operation)

    result = operation.result
    if not result:
        print("Error occurred while generating video.")
        return

    generated_videos = result.generated_videos
    if not generated_videos:
        print("No videos were generated.")
        return

    print(f"Generated {len(generated_videos)} video(s).")
    for n, generated_video in enumerate(generated_videos):
        print(f"Video has been generated: {generated_video.video.uri}")
        client.files.download(file=generated_video.video)
        generated_video.video.save(f"/tmp/story-video-{n}.mp4")
        print(f"Video {generated_video.video.uri} has been downloaded to /tmp/story-video-{n}.mp4.")

if __name__ == "__main__":
    generate()
PY
```

Use the saved video file (e.g., `/tmp/story-video-0.mp4`) for upload.

Re-encode the video for iPhone compatibility before uploading:
```bash
ffmpeg -y -i /tmp/story-video-0.mp4 \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -movflags +faststart \
  /tmp/story-video-encoded.mp4
```

## Step 4: Upload media to R2 via worker API
Base URL:
- If `STORY_API_BASE_URL` is set, use that.
- Else use `https://bedtimestories.bruce-hart.workers.dev`.

Upload image:
```bash
curl -s "$STORY_API_BASE_URL/api/media" \
  -H "X-Story-Token: $STORY_API_TOKEN" \
  -F "file=@/path/to/image.jpg"
```

Upload video:
```bash
curl -s "$STORY_API_BASE_URL/api/media" \
  -H "X-Story-Token: $STORY_API_TOKEN" \
  -F "file=@/tmp/story-video-encoded.mp4"
```

Each response returns `{ "key": "..." }`. Keep those keys.

## Step 5: Create the story record
Send the story to the worker:
```bash
curl -s "$STORY_API_BASE_URL/api/stories" \
  -H "X-Story-Token: $STORY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "TITLE",
    "content": "MARKDOWN_STORY",
    "date": "YYYY-MM-DD",
    "image_url": "IMAGE_KEY",
    "video_url": "VIDEO_KEY"
  }'
```

## Final output to user
Return:
- Title
- Story content (plain text)
- Image key
- Video key
- Story id
