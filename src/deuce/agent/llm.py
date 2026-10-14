"""The agent's chat model, behind one function.

Every node in the graph gets its model from `get_chat_model()`, so the provider
can change in one place. Callers depend on LangChain's chat-model interface,
not on Gemini.

An eval baseline belongs to ONE model. Changing `LLM_MODEL` starts a new
baseline -- otherwise a score change cannot be attributed to the prompt.
"""

from __future__ import annotations

from langchain_core.language_models.chat_models import BaseChatModel

from deuce.config import settings


class LLMNotConfiguredError(RuntimeError):
    """Raised when the key or the model is missing from .env."""


def get_chat_model(model: str | None = None, temperature: float = 0.0, **kwargs) -> BaseChatModel:
    """A Gemini chat model. `model` overrides LLM_MODEL (for comparisons only).

    Temperature 0 by default: the agent writes SQL, and eval runs must be as
    repeatable as the provider allows. It does not make outputs fully
    deterministic. `kwargs` go to the provider class (e.g. timeout, max_retries).
    """
    from langchain_google_genai import ChatGoogleGenerativeAI

    if settings.google_api_key is None:
        raise LLMNotConfiguredError("GOOGLE_API_KEY is not set in .env")
    name = model or settings.llm_model
    if not name:
        raise LLMNotConfiguredError(
            "LLM_MODEL is not set in .env. Choosing the model is a decision; "
            "see lessons/decisions.md."
        )
    return ChatGoogleGenerativeAI(
        model=name,
        api_key=settings.google_api_key.get_secret_value(),
        temperature=temperature,
        **kwargs,
    )
