import asyncio
from typing import Annotated

from fastapi import Depends, Header, HTTPException, status

from app.config import settings

_semaphore = asyncio.Semaphore(max(1, settings.MAX_CONCURRENT))


async def verify_api_key(x_api_key: str | None = Header(default=None)) -> None:
    """Tolak request jika API_KEY di-set tapi header tidak cocok."""
    if not settings.API_KEY:
        return
    if x_api_key != settings.API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key",
        )


async def acquire_slot() -> asyncio.Semaphore:
    return _semaphore


ApiKeyDep = Annotated[None, Depends(verify_api_key)]
