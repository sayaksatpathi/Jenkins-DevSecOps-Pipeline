# ── Stage 1: dependency builder ───────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: minimal runtime ──────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

LABEL org.opencontainers.image.title="JenkinsForge" \
      org.opencontainers.image.description="Container CI/CD pipeline demonstration service" \
      org.opencontainers.image.source="https://github.com/sayaksatpathi/Jenkins-DevSecOps-Pipeline"

# Non-root user
RUN addgroup --system --gid 1001 app \
 && adduser  --system --uid 1001 --ingroup app --no-create-home app

WORKDIR /app

# Install runtime dependencies from builder
COPY --from=builder /install /usr/local

# Copy application source only
COPY src/ src/

RUN chown -R app:app /app

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" \
    || exit 1

ENTRYPOINT ["python", "-m", "uvicorn", "src.main:app", \
            "--host", "0.0.0.0", "--port", "8000", \
            "--log-level", "info"]
