import logging

from fastapi import FastAPI

from .config import settings

logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL, logging.INFO),
    format='{"level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="JenkinsForge",
    version=settings.VERSION,
    description="Container CI/CD pipeline demonstration service",
)


@app.get("/")
async def root() -> dict:
    logger.info("Root endpoint called")
    return {
        "service": settings.APP_NAME,
        "version": settings.VERSION,
        "status": "ok",
    }


@app.get("/health")
async def health() -> dict:
    logger.info("Health check")
    return {
        "service": settings.APP_NAME,
        "version": settings.VERSION,
        "status": "healthy",
    }
