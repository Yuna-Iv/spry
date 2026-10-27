from typing import Annotated, Literal

from pydantic import field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    # The Makefile passes every setting, set or not: an empty one keeps its default.
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", env_ignore_empty=True)

    database_url: str = "postgresql+asyncpg://meetings:meetings@localhost:5432/meetings"
    # Lambda serves one request per instance at a time, so it runs with a pool of 1.
    db_pool_size: int = 5
    db_max_overflow: int = 10
    # Cognito user pool and app client whose ID tokens the API accepts (make deploy-auth).
    cognito_user_pool_id: str = ""
    cognito_client_id: str = ""
    # The pool's jwks.json. Set on AWS, where the function has no internet access; locally the
    # keys are downloaded on first use.
    cognito_jwks: str = ""
    # Agenda parser (app/ai): the Claude model on Amazon Bedrock and the region that serves it.
    # Bedrock may be in another region than the app: the parser reaches it over the internet.
    parser_model: str = "anthropic.claude-opus-5-5"
    bedrock_region: str = "us-east-1"
    # Which Bedrock endpoint serves the model, both with the Anthropic Messages API:
    # "mantle" (bedrock-mantle, current Claude models, IAM action bedrock-mantle:CreateInference)
    # or "runtime" (bedrock-runtime InvokeModel, older Claude models such as Haiku 4.5, IAM
    # action bedrock:InvokeModel; model ids there are inference profiles like us.anthropic....).
    bedrock_api: Literal["mantle", "runtime"] = "mantle"
    # How hard the model thinks (low ... max); "none": not sent, for models without it (Haiku 4.5).
    parser_effort: str = "low"
    # Returns a fixed agenda after a short wait instead of calling the model: for building the
    # screen before Bedrock access is approved. Never set it on a deployment you record.
    parser_fake: bool = False
    cors_origins: Annotated[list[str], NoDecode] = [
        "http://localhost:5173",
        "http://localhost:3000",
    ]

    @field_validator("cors_origins", mode="before")
    @classmethod
    def split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


settings = Settings()
