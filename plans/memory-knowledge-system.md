# 🧠 Hivemind Memory & Knowledge System — Architecture Plan

> **Goal:** Make Hivemind agents have *real* memory — not keyword search, not markdown files, not context window hacks. Actual semantic memory that makes agents feel like they *know you*.

> **Differentiator:** Most AI platforms have no persistent memory, or bolt on basic RAG. Hivemind will have a first-class, multi-layered memory system with automatic embedding, intelligent retrieval, and memory consolidation — built on pgvector, already in the stack.

---

## Current State (What Exists)

| Component | Status |
|---|---|
| `MemoryEntry` model | ✅ Exists, has `embedding` vector(1536) column |
| pgvector extension | ✅ Enabled, HNSW index on embeddings |
| `neighbor` gem (0.6.0) | ✅ In Gemfile, but `has_neighbors` is **commented out** |
| `Memory::Store` service | ✅ Generates embeddings via OpenAI/Ollama |
| `Memory::Search` service | ⚠️ Exists but uses hardcoded fallback (no actual vector search) |
| `MemorySearchExecutor` tool | ⚠️ Uses ILIKE keyword search, ignores embeddings entirely |
| `Sessions::Chat` recall | ⚠️ Uses ILIKE keyword matching, stores memories with `embedding: []` |
| `Sessions::Chat` auto-store | ⚠️ Stores every exchange but with empty embeddings |
| Hashtag actions (#remember, #forget, #search) | ✅ Exist |

**Bottom line:** The pipes are laid but no water is flowing. Embeddings aren't generated on store, vector search isn't used on recall, and the `neighbor` gem integration is disabled.

---

## Phase 1: Light It Up (Wire pgvector + real embeddings)
**Effort:** Small — mostly uncommenting and fixing existing code
**Priority:** 🔴 Critical — foundation for everything else

### 1.1 Enable `has_neighbors` on MemoryEntry
```ruby
# app/models/memory_entry.rb
class MemoryEntry < ApplicationRecord
  has_neighbors :embedding
  # ...
end
```

### 1.2 Fix Memory::Store — already generates embeddings, just make sure they're saved correctly
- Verify the embedding vector is actually persisted (not `[]`)
- Add error handling for API failures (retry once, then store without embedding)

### 1.3 Fix Sessions::Chat#store_memory — generate embeddings on auto-store
- Replace `embedding: []` with actual embedding generation
- **Make it async** — `MemoryEmbeddingJob` so chat responses aren't slowed by embedding API calls
- Store the `MemoryEntry` immediately with `embedding: nil`, enqueue job to backfill

### 1.4 Fix Sessions::Chat#recall_memories — use vector search
```ruby
def recall_memories(agent:, query:)
  query_embedding = generate_embedding(query)
  return [] unless query_embedding

  MemoryEntry.where(agent: agent)
    .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
    .limit(5)
end
```

### 1.5 Fix MemorySearchExecutor — use vector search instead of ILIKE
- Generate embedding for the query
- Use `nearest_neighbors` for retrieval
- Fall back to ILIKE if embedding generation fails

### 1.6 Backfill existing memories
- Rake task: `rails memory:backfill_embeddings`
- Process all `MemoryEntry` records with nil/empty embeddings
- Batch with rate limiting to respect API limits

**Deliverable:** Agents have working semantic memory. Recall is based on meaning, not keywords.

---

## Phase 2: Smart Memory (Auto-chunking, dedup, relevance)
**Effort:** Medium
**Priority:** 🟡 High — makes memory actually useful at scale

### 2.1 Intelligent Chunking
Current: stores every exchange as "User asked: X / Agent responded: Y" — this is noisy.

**New approach:**
- **Conversation summarizer** — after a session ends (or hits N turns), summarize the key points into 1-3 memory entries
- **Fact extraction** — pull out discrete facts ("User's name is Suttles", "Prefers dark mode", "Works at Noldor")
- **Decision logging** — capture decisions and their reasoning

```ruby
# app/jobs/memory_consolidation_job.rb
class MemoryConsolidationJob < ApplicationJob
  queue_as :low

  def perform(session_id)
    session = Session.find(session_id)
    # Use LLM to extract key facts + decisions from transcript
    # Store as typed memory entries
  end
end
```

### 2.2 Memory Types
Add `memory_type` enum to MemoryEntry:

| Type | Description | Example |
|---|---|---|
| `episodic` | What happened (conversation summaries) | "On Feb 23 we planned the memory system" |
| `semantic` | Facts and knowledge | "User works at Noldor Technologies" |
| `procedural` | How to do things | "Deploy hivemind: docker compose up -d" |
| `preference` | User preferences | "Prefers concise responses" |

```ruby
# Migration
add_column :memory_entries, :memory_type, :string, default: "episodic"
add_index :memory_entries, :memory_type
```

### 2.3 Deduplication
Before storing a new memory, check for semantic similarity:
- If similarity > 0.92 with an existing entry → merge/update instead of creating new
- Prevents memory bloat from repetitive conversations

### 2.4 Relevance Scoring
Combine vector similarity with recency for retrieval:
```ruby
# Weighted score: 70% semantic similarity + 30% recency
score = (0.7 * cosine_similarity) + (0.3 * recency_score)
```

Where `recency_score` decays over time (exponential decay, half-life ~7 days).

### 2.5 Memory Capacity Management
- Soft limit per agent (e.g., 10,000 entries)
- When approaching limit, consolidate older episodic memories into summaries
- Never auto-delete semantic/preference memories

**Deliverable:** Agents build clean, organized, non-redundant memory over time.

---

## Phase 3: Automatic Context Injection (The Magic)
**Effort:** Medium
**Priority:** 🟡 High — this is where the UX gets amazing

### 3.1 Pre-chat Memory Retrieval Pipeline
Before every LLM call, automatically:
1. Embed the user's message
2. Retrieve top-K relevant memories (K=5-10)
3. Retrieve recent episodic memories (last 3 sessions)
4. Retrieve all preference memories for this user
5. Inject into system prompt as structured context

### 3.2 Memory-Aware System Prompt Builder
```ruby
# app/services/memory/context_builder.rb
module Memory
  class ContextBuilder
    def call(agent:, query:, session:)
      sections = []

      # Relevant memories (semantic search)
      relevant = semantic_search(agent:, query:, limit: 5)
      sections << format_section("Relevant Context", relevant) if relevant.any?

      # User preferences (always included)
      prefs = preference_memories(agent:)
      sections << format_section("User Preferences", prefs) if prefs.any?

      # Recent history summaries
      recent = recent_episodic(agent:, limit: 3)
      sections << format_section("Recent History", recent) if recent.any?

      sections.join("\n\n")
    end
  end
end
```

### 3.3 Post-chat Memory Pipeline
After every response:
1. **Quick extraction** — pull any new facts/preferences mentioned (lightweight LLM call or regex)
2. **Enqueue consolidation** if session is getting long
3. **Update existing memories** if contradicted (e.g., "actually my name is Matt" updates the name preference)

### 3.4 Token Budget Management
Memory context shouldn't eat the whole context window:
- Budget: max 2,000 tokens for memory context
- Prioritize: preferences > relevant > recent
- Truncate/summarize if over budget

**Deliverable:** Agents seamlessly "remember" without users having to say #remember. It just works.

---

## Phase 4: Cross-Agent Knowledge (Team Intelligence)
**Effort:** Large
**Priority:** 🟢 Nice-to-have for launch, killer post-launch

### 4.1 Shared Knowledge Base
- New model: `KnowledgeEntry` (team-scoped, not agent-scoped)
- Agents can publish to shared knowledge
- Other agents can query team knowledge

### 4.2 Agent-to-Agent Memory Sharing
- Agent A learns something → optionally broadcast to Agent B
- Configurable: which agents share memory, what types

### 4.3 Knowledge Permissions
- Private (agent only) — default
- Team (all agents in team) — opt-in
- Public (all agents on platform) — admin only

**Deliverable:** Multi-agent teams that share institutional knowledge.

---

## Phase 5: Memory UI (User-Facing)
**Effort:** Medium
**Priority:** 🟢 Important for trust and control

### 5.1 Memory Browser
- View all memories for an agent
- Filter by type, date, source
- Search memories semantically

### 5.2 Memory Management
- Edit/delete individual memories
- "Forget this" — user can remove specific memories
- "Remember this" — user can pin important facts
- Export memories (JSON/CSV)

### 5.3 Memory Insights
- "What does this agent know about me?"
- Memory timeline visualization
- Memory health metrics (coverage, staleness)

**Deliverable:** Users trust the system because they can see and control what agents remember.

---

## Implementation Order

```
Phase 1 (Wire it up)          ← 1-2 days, DO THIS FIRST
  └→ Phase 2 (Smart memory)   ← 3-4 days
      └→ Phase 3 (Auto-inject) ← 2-3 days
          └→ Phase 5 (UI)      ← 3-4 days
              └→ Phase 4 (Cross-agent) ← post-launch
```

**Total to launch-ready (Phases 1-3 + basic UI): ~2 weeks**

---

## Technical Notes

- **Embedding model:** `text-embedding-3-small` (1536 dims) — good balance of quality/cost. Can upgrade to `text-embedding-3-large` (3072 dims) later.
- **Ollama fallback:** `nomic-embed-text` for local/free embeddings — currently pads to 1536 dims which is wasteful. Consider separate column or just standardize on OpenAI for now.
- **HNSW index:** Already created. Handles ~1M vectors well. No changes needed.
- **Async everything:** Embedding generation and consolidation MUST be async (Sidekiq jobs). Never block chat responses.
- **Cost:** text-embedding-3-small is $0.02/1M tokens. At 1000 memories/day = ~pennies.

---

## What Makes This AWESOME vs Competition

| Feature | OpenClaw | ChatGPT Memory | Hivemind (after this) |
|---|---|---|---|
| Persistent memory | Markdown files | Flat key-value pairs | Vector-indexed semantic memory |
| Auto-learning | No | Basic | Full conversation extraction |
| Memory types | No | No | Episodic, semantic, procedural, preference |
| Search quality | Runtime semantic | Exact match | Cosine similarity + recency weighting |
| Cross-agent sharing | No | No | Team knowledge base |
| User control | Edit files | On/off toggle | Full CRUD + memory browser |
| Memory consolidation | Manual | Unknown | Automatic summarization + dedup |
| Self-hosted | ✅ | ❌ | ✅ |

**The pitch:** "Hivemind agents don't just respond — they *remember*. Every conversation builds knowledge. Every fact is indexed. Every preference is learned. And it's all yours, running on your hardware."
