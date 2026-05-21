---
stepsCompleted: ["step-01-init", "step-02-discovery", "step-02b-vision", "step-02c-executive-summary", "step-03-success", "step-04-journeys", "step-05-domain", "step-06-usecases", "step-07-requirements", "step-08-architecture", "step-09-constraints", "step-10-dependencies", "step-11-validation"]
inputDocuments:
  - _bmad-output/planning-artifacts/product-brief-rag-smart-ralph.md
  - _bmad-output/planning-artifacts/prfaq-rag-smart-ralph.md
  - _bmad-output/brainstorming/brainstorming-session-2026-05-20-09-04.md
  - _bmad-output/planning-artifacts/research/domain-rag-claude-code-plugins-research-2026-05-20.md
  - _bmad-output/planning-artifacts/research/technical-rag-ralph-loop-architecture-research-2026-05-20.md
workflowType: 'prd'
documentCounts:
  briefCount: 1
  researchCount: 2
  brainstormingCount: 1
  projectDocsCount: 0
classification:
  projectType: developer_tool
  domain: AI-augmented development / RAG for spec-driven development / Harness Engineering
  complexity: High
  projectContext: brownfield
---

# Product Requirements Document - RAG Integration for Smart Ralph

**Author:** Malka
**Date:** 2026-05-20
**Status:** In Progress

## Executive Summary

**Vision Alignment:**

RAG Integration for Smart Ralph transforms the plugin from a spec-driven execution engine into a **learning system** that remembers every implementation decision, failure, and success across all projects. The target users are development teams using Smart Ralph to implement features via specs, who currently face repeated mistakes and lost context between similar tasks.

**Problem Solved:**
- Each spec execution starts with zero context from previous similar tasks
- Errors that took hours to fix recur because no institutional memory exists
- Research and task planning repeat without leveraging past learnings

**What Makes This Special:**

The **Execution Memory** is the unique differentiator. Smart Ralph's chat.md and task_review.md contain:
- Complete failure documentation with root cause analysis
- Decision trails with "why" explanations
- Metrics on what worked vs what didn't

The key moment: **"When an error that took hours to fix is instantly resolved from history"**

This execution memory - structured as detailed logs, reviews, and learnings - becomes searchable knowledge via RAG. Agents retrieve relevant past solutions when encountering similar errors, tasks, or research needs.

**Core Insight:** Smart Ralph doesn't just execute specs - it **memorizes the process**. Each project builds institutional knowledge that benefits future projects.

## Project Classification

| Attribute | Value |
|----------|-------|
| Project Type | developer_tool (Claude Code Plugin) |
| Domain | AI-augmented development / RAG / Harness Engineering |
| Complexity | High |
| Context | Brownfield (extension of existing plugin) |

## Success Criteria

### User Success

**The Moment:** "When an error that took hours to fix is instantly resolved from history"
- Users feel **relieved** when similar errors are resolved without repetitive debugging
- Users feel **empowered** when task planning benefits from past patterns
- Users feel **confident** when research is informed by similar completed specs

### Business Success

| Metric | Baseline | Target |
|--------|----------|--------|
| Task completion time | Without RAG | -15% improvement |
| Research quality | Without context | +20% improvement |
| Context retrieval accuracy | N/A | >70% relevance (sampled) |
| Agent coherence | Inconsistent | Consistent |

**Timeline:**
- 3-month: RAG MVP deployed, basic retrieval working
- 12-month: Execution memory fully indexed, cross-project learning active

### Technical Success

- RAG retrieval latency: <2s
- Index update latency: <5s (async)
- Retrieval accuracy: >70% relevance score
- Graceful degradation when Vector DB unavailable

### Measurable Outcomes

1. **Error Resolution Time:** Average time to resolve recurring errors
2. **Retrieval Hit Rate:** % of retrievals that are relevant (>70% target)
3. **Task Completion Rate:** Tasks completed without intervention

## Product Scope

### MVP
- RAG basic with Qdrant (user-configured)
- Single collection: specs_tasks
- Pre-task retrieval for spec-executor

### Growth (Post-MVP)
- FAISS fallback for local deployments
- Multi-collection (specs, requirements, design)
- Execution memory indexing (chat.md, task_review.md)

### Vision
- Agentic RAG with autonomous retrieval decisions
- Cross-project knowledge graph
- Learning from user feedback

## Integration Flows

### Journey 1: Plugin Developer - Success Path

**Persona:** María, Senior Developer using Smart Ralph to implement feature specs

**Opening Scene:** María starts a new spec for "user authentication" in her project. She's done this before but wants to avoid the 3-hour debugging session from the last auth implementation.

**Rising Action:** 
- RAG retrieves similar auth specs from other projects
- She sees patterns: "Previously, auth token validation failed due to timezone handling"
- Pre-task retrieval shows: "Similar task in project-X used jwt-decode library"

**Climax:** When task-3 fails with "Invalid token format", RAG immediately retrieves: "Project-Y had same error - root cause was missing base64 decoding. Solution: import atob before validation"

**Resolution:** María fixes the issue in 2 minutes instead of 3 hours. The spec completes 20% faster. She documents the lesson in .progress.md for future retrieval.

**Emotional Arc:** Frustration → Relief → Empowerment

---

### Journey 2: Project Team Member - Learning from Execution Memory

**Persona:** Alex, Junior Developer learning from past task reviews

**Opening Scene:** Alex is assigned to implement "password reset flow" - a task similar to one that failed in Q3 last year.

**Rising Action:**
- task_review.md reveals: "Password reset failed because email service wasn't mocked"
- chat.md shows the exact error sequence and root cause analysis
- Alex learns the pattern: Always mock external services before integration tests

**Climax:** Alex successfully implements the task using the documented pattern. His task_review gets flagged as "reused learned pattern" - a new metric tracked by RAG.

**Resolution:** Alex's confidence increases. He's now contributing learned patterns to the team's execution memory.

**Emotional Arc:** Uncertainty → Learning → Confidence

---

### Journey 3: DevOps/Platform Engineer - RAG Configuration

**Persona:** Jordan, DevOps managing Smart Ralph deployment across teams

**Opening Scene:** Jordan needs to deploy Smart Ralph with RAG to 5 teams. Some have Qdrant infrastructure, others don't.

**Rising Action:**
- Plugin defaults to "no RAG" mode - zero breaking changes for existing projects
- For teams with Qdrant: asks for endpoint + API key, creates collection automatically
- For teams without: FAISS fallback activates, data stays local

**Climax:** The configuration flow works seamlessly. Teams don't need to change their workflow - RAG enhances, never breaks.

**Resolution:** All 5 teams deployed. RAG adoption is opt-in based on team readiness. No support tickets for "plugin broke my workflow."

**Emotional Arc:** Concern → Relief → Satisfaction

---

### Journey 4: Support/Troubleshooter - Debugging with Execution Memory

**Persona:** Sam, Developer supporting a failing spec execution

**Opening Scene:** A spec for "payment integration" is blocked. 3 tasks failed. The executor doesn't know why.

**Rising Action:**
- Sam reviews chat.md: "Task-2 failed at verify step - expected output mismatch"
- chat.md shows the exact command run and error output
- Signal history (signals.jsonl) shows: "[HOLD] at task-2, released after manual intervention"

**Climax:** The failure root cause: "Payment API changed their response format last week. Test was using hardcoded expected output." Solution: Update expected output to handle new format.

**Resolution:** Spec unblocked. Sam files a documentation PR to update payment API integration guidelines.

**Emotional Arc:** Confusion → Investigation → Clarity

---

### Integration Flow Requirements Summary

| Integration Flow | Revealed Capability | Priority |
|---------|---------------------|----------|
| Maria's Auth Flow | RAG retrieval on task start | MVP |
| Alex's Learning | task_review.md indexing | Growth |
| Jordan's Config | RAG opt-in flow, graceful degradation | MVP |
| Sam's Debugging | chat.md detailed logging, signal history | MVP |

## Use Cases

### UC-1: Pre-Task Retrieval
**Actor:** spec-executor
**Trigger:** New task assignment received
**Flow:**
1. spec-executor receives task (e.g., "Implement user authentication")
2. RAGService.retrieve(task_description, collection="specs_tasks", top_k=5)
3. Retrieved chunks injected into task prompt
4. spec-executor executes with enriched context

### UC-2: On-Error Retrieval
**Actor:** spec-executor
**Trigger:** Task execution fails
**Flow:**
1. Task fails with error message
2. RAGService.retrieve(error_message, collection="execution_memory", top_k=3)
3. Past solutions retrieved with root cause
4. spec-executor retries with suggested fix

### UC-3: Bulk Indexing
**Actor:** DevOps/Platform
**Trigger:** RAG enabled on existing project
**Flow:**
1. User runs `/ralphharness:index-all --force`
2. System scans specs/ directory
3. All specs indexed: tasks.md, requirements.md, design.md, chat.md, task_review.md
4. Report generated: "Indexed X specs, Y chunks, Z errors"

### UC-4: Graceful Degradation
**Actor:** System
**Trigger:** Vector DB unavailable
**Flow:**
1. RAGService attempts connection to Qdrant
2. Connection fails (timeout, auth error, endpoint unreachable)
3. RAGService falls back to FAISS local index
4. If no local index, RAG continues disabled
5. No breaking changes to plugin behavior

### UC-5: On-Review Retrieval
**Actor:** external-reviewer
**Trigger:** Reviewer evaluates task output
**Flow:**
1. external-reviewer completes evaluation
2. RAGService.retrieve(task_description, collection="reviews", top_k=3)
3. Past review patterns retrieved with feedback types
4. Reviewer receives contextual hints from similar reviews
5. Review quality improved through pattern matching

### UC-6: Pre-Research Retrieval
**Actor:** research-analyst
**Trigger:** Research phase starts for new feature
**Flow:**
1. research-analyst begins investigation for new spec
2. RAGService.retrieve(feature_domain, collection="specs_research", top_k=5)
3. Past research findings retrieved from similar specs
4. Research quality improved by learning from previous approaches
5. Avoids duplicating research already done in other projects

### UC-7: Pre-Requirements Retrieval
**Actor:** requirements-generator
**Trigger:** Requirements phase starts
**Flow:**
1. requirements-generator starts writing requirements
2. RAGService.retrieve(usecase_description, collection="specs_requirements", top_k=3)
3. Successful requirement patterns retrieved
4. Requirements enriched with proven patterns
5. Quality improved by referencing validated requirements

### UC-8: Pre-Design Retrieval
**Actor:** design-analyst
**Trigger:** Design phase starts
**Flow:**
1. design-analyst begins architecture/design work
2. RAGService.retrieve(technical_context, collection="specs_design", top_k=3)
3. Design patterns from similar features retrieved
4. Design choices informed by past implementations
5. Reduces design iteration by learning from others

### UC-9: Pre-Tasks Retrieval
**Actor:** task-planner
**Trigger:** Task decomposition starts
**Flow:**
1. task-planner begins breaking down spec into tasks
2. RAGService.retrieve(spec_summary, collection="specs_tasks", top_k=5)
3. Task templates and decompositions from similar specs retrieved
4. Task breakdown enriched with proven patterns
5. More accurate estimates based on historical data

## Functional Requirements

### FR-1: RAG Service Core
- RAGService class with retrieve() and index() methods
- Support Qdrant and FAISS providers
- Configuration via .ralphharness.local.md

### FR-2: Retrieval Trigger Points
**Planning Phases:**
- Pre-research: Before research-analyst starts investigation
- Pre-requirements: Before requirements generation
- Pre-design: Before design phase
- Pre-tasks: Before task decomposition

**Execution Phases:**
- Pre-task: Before spec-executor starts task
- On-error: When task fails (non-zero exit)
- On-review: When external-reviewer evaluates

### FR-3: Collection Management
- specs_tasks: Index tasks.md by task
- specs_requirements: Index requirements.md by section
- specs_design: Index design.md by section
- specs_research: Index research.md by findings
- execution_memory: Index chat.md by message, task_review.md by row

### FR-4: Signal Integration
- RETRIEVAL_REQUEST: Written before retrieval
- RETRIEVAL_COMPLETE: Written after successful retrieval
- RETRIEVAL_FAILED: Written on retrieval error
- INDEXING_QUEUED: Written after task completion

### FR-5: Bulk Index Command
- `/ralphharness:index-all [--force]` scans specs/
- Reports index statistics
- Supports incremental updates
- **Streaming index**: For projects with >100 specs, process in batches of 50

### FR-6: Data Integrity
- Each chunk has `indexed_at` timestamp and content hash
- Post-index validation verifies checksum matches source
- Staleness detection: retrieve returns `index_age_days` metadata

## Architecture

### Component Architecture

```
┌──────────────────────────────────────────────────────┐
│                   Smart Ralph Plugin                │
│                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────┐ │
│  │RAGService   │───▶│VectorDB     │◀───│Embedder  │ │
│  │             │    │(Qdrant/FAISS)   │(OpenAI/  │ │
│  │retrieve()   │    │              │    │Local)   │ │
│  │index()      │    └─────────────┘    └──────────┘ │
│  └─────────────┘                                     │
│        │                                            │
│        ▼                                            │
│  ┌─────────────────────────────────────────────┐    │
│  │           Ralph Loop Integration           │    │
│  │  spec-executor → RAG → Context Enrichment  │    │
│  └─────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### RAGService Interface

```python
class RAGService:
    def __init__(self, config: RAGConfig)
    def retrieve(query: str, collection: str, top_k: int) -> List[Chunk]
    def index(chunks: List[Chunk], collection: str) -> bool
    def health_check() -> bool
```

### Signal Flow Integration

The signal protocol (`signals.jsonl`) tracks RAG operations:

```
[T=0] spec-executor → coordinator: "Starting task: Implement auth"
[T=1] coordinator → RAGService: RETRIEVAL_REQUEST {query: "auth", collection: "specs_tasks"}
[T=2] RAGService → Qdrant: retrieve(query, top_k=5)
[T=3] Qdrant → RAGService: [chunks]
[T=4] RAGService → coordinator: RETRIEVAL_COMPLETE {chunks: 5}
[T=5] coordinator → spec-executor: Enriched context injected
[T=6] spec-executor → coordinator: TASK_COMPLETE
[T=7] coordinator → RAGService: INDEXING_QUEUED {spec: "auth", chunks: 12}
```

**Signal Types for RAG:**
| Signal | When | Payload |
|--------|------|---------|
| RETRIEVAL_REQUEST | Before retrieval | query, collection, top_k |
| RETRIEVAL_COMPLETE | After success | chunks returned, latency_ms |
| RETRIEVAL_FAILED | On error | error, fallback_used |
| INDEXING_QUEUED | After task complete | spec_name, chunk_count |

### Ralph Loop Integration Points

RAGService integrates via existing hooks:

```python
# Via PreTask hook (for UC-1: Pre-Task Retrieval)
@hook("PreTask")
def on_pre_task(task_description: str) -> dict:
    chunks = rag_service.retrieve(task_description, collection="specs_tasks", top_k=5)
    return {"enriched_context": chunks}

# Via PostTask hook (for UC-2: On-Error Retrieval)
@hook("PostTask")
def on_post_task(task_result: dict) -> dict:
    if task_result["exit_code"] != 0:
        chunks = rag_service.retrieve(task_result["error"], collection="execution_memory", top_k=3)
        return {"suggested_fix": chunks}
    return {}

# Via PostReview hook (for UC-5: On-Review Retrieval)
@hook("PostReview")
def on_post_review(review_result: dict) -> dict:
    chunks = rag_service.retrieve(review_result["task"], collection="reviews", top_k=3)
    return {"review_hints": chunks}
```

## Constraints

### C-1: Backward Compatibility
- Plugin MUST work without RAG (zero breaking changes)
- Default mode: RAG disabled

### C-2: Graceful Degradation
- If Vector DB unavailable, continue without RAG
- Never block execution due to RAG failures

### C-3: Data Privacy
- chat.md and task_review.md may contain sensitive info
- Cross-project retrieval requires explicit opt-in
- **Collection isolation**: Each project has separate RAG collection; no cross-project retrieval without explicit flag

### C-4: Performance
- Retrieval latency: <2s (target)
- Index update: async, <5s (target)
- No blocking on indexing during task execution
- **Async retrieval**: Non-blocking PreTask hook with 2s timeout; fallback on timeout

### C-5: Resource Management
- Bulk index MUST check available RAM before loading
- Stream indexing for projects with >100 specs
- OOM prevention on machines with <8GB available memory

### C-6: Security Hardening
- **Sanitization layer**: Before indexing, content is scanned for API keys, tokens, passwords using regex patterns
- **Content validation**: Index content must pass allowlist validation (no injected malicious specs)
- **Rate limiting**: Bulk index command limited to 1 request per minute per project
- **Auth required**: Qdrant endpoints must have authentication enabled
- **Integrity checks**: FAISS index files signed with HMAC to detect tampering

## Dependencies

### D-1: External Services
- Qdrant server (if using Qdrant provider)
- OpenAI API (if using OpenAI embeddings)

### D-2: Libraries
- qdrant-client (Python)
- faiss-cpu or faiss-gpu
- sentence-transformers (for local embeddings fallback)

### D-3: Internal
- Smart Ralph hooks system (PreTask, PostTask)
- signals.jsonl protocol
- chat.md format

## Validation Strategy

### V-1: Unit Tests
- RAGService.retrieve() with mock Vector DB
- RAGService.index() with mock Vector DB
- Graceful degradation scenarios

### V-2: Integration Tests
- End-to-end retrieval with real Qdrant/FAISS
- Bulk index command with test specs
- Ralph Loop integration with RAG enabled

### V-3: Performance Tests
- Retrieval latency <2s (p95)
- Index update latency <5s (p95)
- Concurrent retrieval handling

### V-4: User Validation
- Jordan (DevOps) validates config flow
- Maria (Developer) validates retrieval quality
- Sam (Support) validates debugging flows