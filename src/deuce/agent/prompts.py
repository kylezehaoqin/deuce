"""Prompts for the analytics agent.

Increment 2 wires this into a LangGraph graph. The graph is mechanical; the
routing prompt is the part that decides whether the product works, so it lives
here on its own and gets its own eval cases.

    SYSTEM_PROMPT is written by hand. See the TODO below.
"""

from __future__ import annotations

from enum import StrEnum


class Route(StrEnum):
    """Where a question goes after the router node.

    Keep this list small. Every route is a branch the eval set has to cover, and
    a router with six options is a router you cannot debug.
    """

    SQL = "sql"
    """Answerable by querying the marts. Numbers, rates, counts, comparisons."""

    SEMANTIC = "semantic"
    """Answerable from match notes / narrative via pgvector. Fuzzy, descriptive."""

    HYBRID = "hybrid"
    """Needs both: a number from SQL plus context that only prose carries."""

    REFUSE = "refuse"
    """Not answerable from this data at all. Saying so is a correct answer."""


# Rendered into SYSTEM_PROMPT at request time. Generated from the dbt manifest
# so the agent's view of the schema can never drift from the warehouse.
SCHEMA_CONTEXT_PLACEHOLDER = "{schema_context}"


# ============================================================================
#  TODO(kyle): write SYSTEM_PROMPT.
#
#  WHY THIS ONE IS YOURS
#
#  This prompt is where the project's two layers meet. It is also the single
#  artifact an interviewer can read in 60 seconds and tell whether you have
#  actually built an agent or just called an LLM. Do not let a model write it.
#
#  IT HAS TO DO FOUR THINGS
#
#  1. ROUTE.  Given a question, pick a Route above. The hard cases are the ones
#     that *sound* semantic but are not:
#
#       "Who's the biggest first-strike player?"      -> SQL (win rate, <=4 shots)
#       "Does Alcaraz look nervous on break points?"  -> REFUSE (not in the data)
#       "Why did Sinner lose that match?"             -> HYBRID, or REFUSE?
#
#     That third one is the interesting one. Decide where the line is, and say
#     so explicitly in the prompt -- vague instructions produce vague routing.
#
#  2. GROUND.  Every answer cites the rows it came from: match ids, sample size,
#     the filter applied. The brief's promise is "grounded, cited answers"; this
#     is the sentence that has to make that true.
#
#  3. REFUSE WELL.  Under-supported is worse than unanswered. Set an explicit
#     floor -- questions.yml keeps saying "if N < 20 say the sample is thin".
#     Put a number in the prompt, not an adjective.
#
#  4. SPEAK TENNIS.  "62% of second serves to the T" is data. "She goes to the
#     body under pressure and it's readable" is an answer. The audience is
#     tennis-literate; the prompt should say so.
#
#  TRADE-OFFS TO SETTLE BEFORE YOU WRITE
#
#  - Router in the system prompt, or a separate cheap classifier call?
#    One call is faster and keeps context; two are independently evaluable and
#    let you run a small local model on the routing. Your eval harness is the
#    reason to care -- you can only measure what you can isolate.
#
#  - How much schema goes in? All mart DDL is accurate but expensive and buries
#    the instructions. Descriptions only is cheap but invites invented columns.
#
#  - Does the agent show its SQL? Showing it makes every answer auditable and
#    makes the demo land. It also makes every mistake visible. (Show it.)
#
#  START SMALLER THAN YOU THINK. Write the SQL-only version first, run the 16
#  cases in questions.yml against it, and let the failures tell you what the
#  routing rules need to say. A prompt written against observed failures beats
#  one written against imagined ones.
# ============================================================================

SYSTEM_PROMPT = """\
TODO: see the notes above.
"""


ROUTER_EXAMPLES: list[tuple[str, Route]] = [
    # Few-shot pairs for the router. Fill these from the cases that actually
    # fail once the agent runs -- not from guesses.
    # ("Who's the biggest first-strike player on tour?", Route.SQL),
]
