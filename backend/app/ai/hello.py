"""`make llm-hello`: the first call to Claude on Bedrock, from your laptop."""

from anthropic import AnthropicBedrockMantle

from app.config import settings


def main() -> None:
    client = AnthropicBedrockMantle(aws_region=settings.bedrock_region)
    msg = client.messages.create(
        model=settings.parser_model,
        max_tokens=1024,
        output_config={"effort": "low"},  # short, cheap answers
        messages=[{"role": "user", "content": "In one sentence: what is an ISO week?"}],
    )
    print(next(b.text for b in msg.content if b.type == "text"))
    print(f"model={settings.parser_model} region={settings.bedrock_region}")
    print(
        f"stop_reason={msg.stop_reason} input_tokens={msg.usage.input_tokens} "
        f"output_tokens={msg.usage.output_tokens}"
    )


if __name__ == "__main__":
    main()
