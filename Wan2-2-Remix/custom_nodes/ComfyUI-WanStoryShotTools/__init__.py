import json
import re


def _clean_text(value):
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    return str(value).strip()


def _strip_json_fence(text):
    text = _clean_text(text)
    fenced = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.IGNORECASE | re.DOTALL)
    if fenced:
        return fenced.group(1).strip()
    return text


def _safe_filename(value, fallback):
    value = _clean_text(value) or fallback
    value = value.lower()
    value = re.sub(r"[^a-z0-9._-]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("._-")
    return value or fallback


def _merge_negative(base, shot_negative):
    base = _clean_text(base)
    shot_negative = _clean_text(shot_negative)
    if base and shot_negative:
        return f"{base}, {shot_negative}"
    return base or shot_negative


def _continuity_text(continuity_bible):
    if not isinstance(continuity_bible, dict):
        return _clean_text(continuity_bible)
    parts = []
    for key in (
        "character_identity",
        "outfit_lock",
        "subject_or_product_lock",
        "visual_style",
    ):
        value = _clean_text(continuity_bible.get(key))
        if value:
            parts.append(f"{key}: {value}")
    return "\n".join(parts)


def _preservation_block(continuity_bible):
    bible = _continuity_text(continuity_bible)
    base = (
        "Use the continuity bible. Preserve the exact same main subject across this shot. "
        "Do not redesign the character, face, outfit, product shape, logo, label, color, "
        "material, accessories, or any locked subject detail."
    )
    return f"{base}\n{bible}".strip() if bible else base


class WanStoryPlanPromptBuilder:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "story_subject": ("STRING", {"multiline": True, "default": ""}),
                "subject_description": ("STRING", {"multiline": True, "default": ""}),
                "key_points": ("STRING", {"multiline": True, "default": ""}),
                "audience_viewer": ("STRING", {"multiline": True, "default": ""}),
                "tone_style": ("STRING", {"multiline": True, "default": ""}),
                "shot_count": ("INT", {"default": 6, "min": 1, "max": 20, "step": 1}),
                "total_duration_target": ("STRING", {"multiline": False, "default": "18 seconds"}),
                "reference_usage_guide": ("STRING", {"multiline": True, "default": ""}),
                "raw_story_request": ("STRING", {"multiline": True, "default": ""}),
                "character_subject_lock": ("STRING", {"multiline": True, "default": ""}),
                "output_fps": ("FLOAT", {"default": 20.0, "min": 1.0, "max": 120.0, "step": 1.0}),
            }
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("story_planner_prompt",)
    FUNCTION = "build"
    CATEGORY = "Wan2.2 Remix/Story"

    def build(
        self,
        story_subject,
        subject_description,
        key_points,
        audience_viewer,
        tone_style,
        shot_count,
        total_duration_target,
        reference_usage_guide,
        raw_story_request,
        character_subject_lock,
        output_fps,
    ):
        prompt = f"""
You are a senior story planner, video director, and prompt engineer for a ComfyUI workflow that generates one shot at a time with FLUX.1 Kontext first-frame generation and Wan2.2 image-to-video.

Create a complete multi-shot video plan from the user's inputs. The user may write in Thai or any language. Understand the intent, then write all generation prompts in natural English.

Output only valid JSON. Do not output markdown, comments, explanations, code fences, or trailing text. If information is missing, make a conservative creative choice that preserves the user's intent.

Required top-level schema:
{{
  "story_title": "short English title",
  "fps": {int(round(float(output_fps)))},
  "continuity_bible": {{
    "character_identity": "identity details to preserve, or empty string",
    "outfit_lock": "outfit details to preserve, or empty string",
    "subject_or_product_lock": "main subject/product/location details to preserve",
    "visual_style": "lighting, camera style, vertical composition, realism/style lock"
  }},
  "shots": [
    {{
      "shot_index": 1,
      "filename_suffix": "shot_01_hook",
      "goal": "Opening / Hook",
      "duration_seconds": 2,
      "frames": 40,
      "continuity_from_previous": "",
      "start_state": "clear visual start state",
      "still_prompt": "English FLUX Kontext first-frame prompt, with preservation wording",
      "motion_prompt": "English Wan image-to-video motion prompt with visible action beats",
      "camera_prompt": "shot size, camera movement, framing",
      "end_state": "clear visual end state",
      "handoff_to_next": "continuity handoff for next shot",
      "negative_prompt": "shot-specific negatives"
    }}
  ]
}}

Planning rules:
- Create exactly {int(shot_count)} shots.
- Use fps {int(round(float(output_fps)))} when calculating frames.
- Derive duration_seconds per shot from the total duration target; do not make all shots equal unless the story really needs that.
- frames must equal round(duration_seconds * fps), minimum 1.
- Choose shot goals according to the story type. Generic stories should usually progress through opening/hook, context/setup, main action/reveal, development/detail, result/turning point, and closing/memory shot when the requested shot count allows it.
- Product review stories should usually use short hook and CTA shots, medium problem/reveal/result shots, and a longer feature demo shot. Keep product label/package visibility clear in reveal, demo, and packshot moments.
- Tutorials should emphasize step-by-step clarity, travel vlogs should emphasize location/movement/atmosphere, fashion lookbooks should emphasize outfit reveal/pose/movement/detail/final look, and short films should emphasize setup/reveal/emotional ending.
- Build one continuity_bible for the whole story and make every shot follow it.
- Every still_prompt and motion_prompt must preserve the continuity bible and locked subject details.
- Follow the user's Reference Usage Guide exactly. Common setup: Ref 1 is presenter/character identity, Ref 2 is product/package/detail sheet, and Ref 3 is optional location/lighting/background/mood. If Ref 3 is not provided, invent a clean believable scene/background that matches the subject category and usage.
- If references conflict, presenter identity from Ref 1 and product/package/details from Ref 2 have priority over pose, lighting, background, and style.
- Do not let the subject, face, outfit, product, logo, packaging, location, or key locked details drift between shots.
- Keep prompts concrete, visual, and suitable for vertical short-form video unless the user's request says otherwise.
- Do not change model settings, resolution, steps, LoRA, CRF, or performance settings.

User inputs:
Story Subject:
{_clean_text(story_subject)}

Subject Description:
{_clean_text(subject_description)}

Key Points / Must Include:
{_clean_text(key_points)}

Audience / Viewer:
{_clean_text(audience_viewer)}

Tone / Style:
{_clean_text(tone_style)}

Shot Count:
{int(shot_count)}

Total Duration Target:
{_clean_text(total_duration_target)}

Reference Usage Guide:
{_clean_text(reference_usage_guide)}

Raw Story Request / Goal:
{_clean_text(raw_story_request)}

Character / Subject Lock:
{_clean_text(character_subject_lock)}
""".strip()
        return (prompt,)


class WanStoryShotParser:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "story_mode": ("BOOLEAN", {"default": False}),
                "story_json": ("STRING", {"multiline": True, "default": ""}),
                "shot_index": ("INT", {"default": 1, "min": 1, "max": 999, "step": 1}),
                "raw_positive_prompt": ("STRING", {"multiline": True, "default": ""}),
                "normal_motion_direction": ("STRING", {"multiline": True, "default": ""}),
                "normal_camera_direction": ("STRING", {"multiline": True, "default": ""}),
                "enhance_prompt": ("BOOLEAN", {"default": True}),
                "enhance_flux_still_prompt": ("BOOLEAN", {"default": True}),
                "use_story_motion_enhancer": ("BOOLEAN", {"default": False}),
                "normal_filename_prefix": ("STRING", {"multiline": False, "default": "%date:yyyy-MM-dd%/%date:yyyyMMdd_hhmmss%_Wan2.2"}),
                "output_fps": ("FLOAT", {"default": 20.0, "min": 1.0, "max": 120.0, "step": 1.0}),
                "normal_wan_negative_prompt": ("STRING", {"multiline": True, "default": ""}),
                "normal_flux_negative_prompt": ("STRING", {"multiline": True, "default": ""}),
            }
        }

    RETURN_TYPES = (
        "STRING",
        "STRING",
        "STRING",
        "STRING",
        "STRING",
        "STRING",
        "INT",
        "STRING",
        "STRING",
        "STRING",
        "BOOLEAN",
        "BOOLEAN",
        "STRING",
        "STRING",
        "FLOAT",
        "STRING",
        "STRING",
        "STRING",
        "STRING",
        "STRING",
    )
    RETURN_NAMES = (
        "selected_still_prompt",
        "selected_motion_prompt",
        "selected_camera_prompt",
        "selected_negative_prompt",
        "selected_video_prompt",
        "effective_motion_direction",
        "selected_frames",
        "filename_prefix",
        "shot_goal",
        "continuity_bible_text",
        "effective_enhance_prompt",
        "effective_enhance_flux_still",
        "final_wan_negative_prompt",
        "final_flux_negative_prompt",
        "duration_seconds",
        "continuity_from_previous",
        "start_state",
        "end_state",
        "handoff_to_next",
        "selected_shot_debug_text",
    )
    FUNCTION = "parse"
    CATEGORY = "Wan2.2 Remix/Story"

    def parse(
        self,
        story_mode,
        story_json,
        shot_index,
        raw_positive_prompt,
        normal_motion_direction,
        normal_camera_direction,
        enhance_prompt,
        enhance_flux_still_prompt,
        use_story_motion_enhancer,
        normal_filename_prefix,
        output_fps,
        normal_wan_negative_prompt,
        normal_flux_negative_prompt,
    ):
        raw_positive_prompt = _clean_text(raw_positive_prompt)
        normal_wan_negative_prompt = _clean_text(normal_wan_negative_prompt)
        normal_flux_negative_prompt = _clean_text(normal_flux_negative_prompt)
        if not story_mode:
            return (
                raw_positive_prompt,
                raw_positive_prompt,
                _clean_text(normal_camera_direction),
                "",
                raw_positive_prompt,
                _clean_text(normal_motion_direction),
                1,
                _clean_text(normal_filename_prefix) or "%date:yyyy-MM-dd%/%date:yyyyMMdd_hhmmss%_Wan2.2",
                "Normal mode",
                "",
                bool(enhance_prompt),
                bool(enhance_flux_still_prompt),
                normal_wan_negative_prompt,
                normal_flux_negative_prompt,
                0.0,
                "",
                "",
                "",
                "",
                "Normal mode",
            )

        try:
            story = json.loads(_strip_json_fence(story_json))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Story JSON is not valid JSON: {exc}") from exc

        shots = story.get("shots")
        if not isinstance(shots, list) or not shots:
            raise ValueError("Story JSON must contain a non-empty shots array.")

        selected = None
        for shot in shots:
            if int(shot.get("shot_index", -1)) == int(shot_index):
                selected = shot
                break
        if selected is None:
            available = ", ".join(str(s.get("shot_index", "?")) for s in shots)
            raise ValueError(f"Shot index {shot_index} was not found. Available shot indexes: {available}")

        continuity_bible = story.get("continuity_bible", {})
        preserve = _preservation_block(continuity_bible)
        still_prompt = _clean_text(selected.get("still_prompt"))
        motion_prompt = _clean_text(selected.get("motion_prompt") or selected.get("action"))
        camera_prompt = _clean_text(selected.get("camera_prompt"))
        negative_prompt = _clean_text(selected.get("negative_prompt"))
        continuity_from_previous = _clean_text(selected.get("continuity_from_previous"))
        start_state = _clean_text(selected.get("start_state"))
        end_state = _clean_text(selected.get("end_state"))
        handoff_to_next = _clean_text(selected.get("handoff_to_next"))

        if not still_prompt:
            raise ValueError(f"Shot {shot_index} is missing still_prompt.")
        if not motion_prompt:
            raise ValueError(f"Shot {shot_index} is missing motion_prompt.")

        still_prompt = f"{preserve}\n\n{still_prompt}".strip()
        motion_prompt = f"{preserve}\n\n{motion_prompt}".strip()
        video_prompt = motion_prompt
        if camera_prompt:
            video_prompt = f"{video_prompt}\n\nCAMERA_DIRECTION:\n{camera_prompt}".strip()

        frames = selected.get("frames")
        duration_seconds = selected.get("duration_seconds")
        if frames is None:
            duration = float(duration_seconds or 1)
            frames = round(duration * float(output_fps))
        frames = max(1, int(round(float(frames))))
        duration_seconds = float(duration_seconds or (frames / float(output_fps)))

        suffix = _safe_filename(selected.get("filename_suffix"), f"shot_{int(shot_index):02d}")
        filename_prefix = f"%date:yyyy-MM-dd%/%date:yyyyMMdd_hhmmss%_Wan2.2_story_{suffix}"
        final_wan_negative = _merge_negative(normal_wan_negative_prompt, negative_prompt)
        final_flux_negative = _merge_negative(normal_flux_negative_prompt, negative_prompt)
        debug = "\n".join(
            part
            for part in (
                f"shot_index: {int(shot_index)}",
                f"goal: {_clean_text(selected.get('goal'))}",
                f"duration_seconds: {duration_seconds:g}",
                f"frames: {frames}",
                f"continuity_from_previous: {continuity_from_previous}",
                f"start_state: {start_state}",
                f"end_state: {end_state}",
                f"handoff_to_next: {handoff_to_next}",
                f"negative_prompt: {negative_prompt}",
            )
            if part.split(": ", 1)[-1]
        )

        return (
            still_prompt,
            motion_prompt,
            camera_prompt,
            negative_prompt,
            video_prompt,
            "",
            frames,
            filename_prefix,
            _clean_text(selected.get("goal")),
            _continuity_text(continuity_bible),
            bool(use_story_motion_enhancer),
            False,
            final_wan_negative,
            final_flux_negative,
            duration_seconds,
            continuity_from_previous,
            start_state,
            end_state,
            handoff_to_next,
            debug,
        )


NODE_CLASS_MAPPINGS = {
    "WanStoryPlanPromptBuilder": WanStoryPlanPromptBuilder,
    "WanStoryShotParser": WanStoryShotParser,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "WanStoryPlanPromptBuilder": "Wan Story Plan Prompt Builder",
    "WanStoryShotParser": "Wan Story Shot Parser",
}
