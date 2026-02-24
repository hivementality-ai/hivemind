# Token Efficiency Best Practices

Every message an agent sends or receives costs tokens. Here's how to keep costs under control.

## How Token Costs Add Up

Each message to an LLM includes:

| Component | Typical Size | Notes |
|-----------|-------------|-------|
| System prompt | ~2K tokens | Agent identity, role, workspace info, skills |
| Memory context | ~250 tokens | Preferences, relevant memories, recent history |
| Conversation summary | ~200 tokens | Compressed older conversation (auto-generated) |
| Last few messages | ~500 tokens | Raw recent transcript (last 4 messages) |
| **Total per request** | **~1K-3K tokens** | Before the agent even reads your message |

With prompt caching (Anthropic), the system prompt is cached after the first call and subsequent requests pay ~10% of the original cost for that portion.

## Sessions: Reuse, Don't Recreate

**Starting a new session is more expensive than continuing one.**

- A new session has no conversation summary — the system prompt is sent cold (no cache hit).
- Prompt caching has a 5-minute TTL. If you create a new session, the cache resets.
- Each session that accumulates enough messages triggers a summarization job, which itself costs tokens (though it uses the cheapest model available).

**Best practices:**
- Reuse existing sessions for ongoing work with an agent.
- Don't start a new session for every question — keep a conversation going.
- Use new sessions for genuinely separate tasks or contexts.

## Memory: Quality Over Quantity

The memory system stores exchanges and extracts facts automatically. Low-quality memories (greetings, small talk) are filtered out, but you can help:

- Give agents substantive messages rather than multiple short pings.
- Instead of "hey" → wait → "can you do X?", just say "hey, can you do X?"
- Fewer messages = fewer memory entries = less noise in future context retrieval.

## Model Selection

Not every message needs the most powerful model:

- **Casual chat / simple questions** → Haiku or GPT-5.2-nano
- **Code review / complex reasoning** → Sonnet or GPT-5.2
- **Architecture / critical decisions** → Opus (use sparingly)

The summarization system automatically uses the cheapest available model.

## Tools and Long Sessions

Tool-heavy sessions can generate large transcript entries (tool inputs/outputs). The system keeps only the last 4 raw messages and summarizes the rest, but during an active tool loop, context can still grow. Keep this in mind for agents that run many tools in sequence.

## Monitoring

Check the **Usage Tracker** in the UI to spot:
- Agents with unusually high input token counts
- Sessions with many small exchanges (candidate for consolidation)
- Cost trends over time
