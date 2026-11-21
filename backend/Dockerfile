# Two targets from one Dockerfile:
#   base   - the plain FastAPI container: Cloud Run, `docker run`, docker compose
#   lambda - base + Lambda Web Adapter, for AWS Lambda (the default: the last stage)
FROM python:3.14-slim AS base

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-install-project

COPY . .

EXPOSE 8000
# Cloud Run passes the port in PORT (8080); everywhere else it is unset and the app listens on 8000.
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

FROM base AS lambda
# Lets the unchanged uvicorn app run on AWS Lambda (AWS_LWA_PORT=8000 in infra/backend.yaml).
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0 /lambda-adapter /opt/extensions/lambda-adapter
