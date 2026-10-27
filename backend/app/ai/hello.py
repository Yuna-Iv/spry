"""`make llm-hello`: the first call to Claude on Bedrock, from your laptop."""

import sys

import anthropic

from app.ai.agenda import effort, get_client
from app.config import settings


def main() -> None:
    where = (
        f"model={settings.parser_model} api={settings.bedrock_api} region={settings.bedrock_region}"
    )
    try:
        msg = get_client().messages.create(
            model=settings.parser_model,
            max_tokens=1024,
            messages=[{"role": "user", "content": "In one sentence: what is an ISO week?"}],
            **effort(),
        )
    except anthropic.APIError as e:
        print(f"Bedrock call failed: {type(e).__name__}: {e}\n({where})", file=sys.stderr)
        sys.exit(1)
    print(next(b.text for b in msg.content if b.type == "text"))
    print(where)
    print(
        f"stop_reason={msg.stop_reason} input_tokens={msg.usage.input_tokens} "
        f"output_tokens={msg.usage.output_tokens}"
    )


if __name__ == "__main__":
    main()
