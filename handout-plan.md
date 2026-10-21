# Plan: Signal Over Noise — Handout & TODO

## Top-Level Overview

Combine three existing PDFs into a single linear Word handout in English for workshop participants (Box / GitHub distribution). Additionally create a high-level TODO.md capturing the full lab concept as a concise checklist — starting where the installation guide ends (after the Go/No-Go test) and covering: baseline, probabilistic sampling (50 %, 10 %), tail sampling, and the MCP/AI advisor.

Title: **Signal Over Noise: Smarter OpenTelemetry Sampling with AI**

---

## Sub-Task 1 — Word Handout Document

**Intent:** Produce a single, readable end-to-end lab guide for participants. Chronological structure: Install → Baseline → Sampling → MCP/AI.

**Expected Outcomes:**
- File `OTel_Sampling_Lab_Handout.docx` exists in the project root
- Document is in English
- Three clearly labelled parts with consistent heading hierarchy

**Document Structure:**
1. Cover / Title page — "Signal Over Noise: Smarter OpenTelemetry Sampling with AI"
2. **Part 1 – Full Installation** (source: PDF 1, all 24 chapters) — ends with Go/No-Go checklist
3. **Part 2 – Baseline & Sampling** (source: PDF 3 didactic structure + PDF 2 technical snippets)
   - Mental model
   - Step 1: 100 % Baseline
   - Step 2: 50 % Probabilistic Sampling
   - Step 3: 10 % Probabilistic Sampling
   - Step 4: Tail Sampling
4. **Part 3 – MCP Sampling Advisor & AI** (source: PDF 3 Step 3 + PDF 2 Ch. 9–12)
   - Build the MCP server
   - Test with MCP Inspector
   - Instruct the AI
   - Translate AI recommendation into a policy
   - Before/After measurement
5. Troubleshooting & Rollback (from PDF 2 Ch. 13)
6. References (from PDF 2 Ch. 15)

**Status:** [ ] pending

---

## Sub-Task 2 — TODO.md

**Intent:** Provide a high-level concept checklist of everything still to be done after the installation is complete. Not a detailed implementation guide — just the ordered items that represent the full lab story.

**Expected Outcomes:**
- File `TODO.md` exists in the project root
- Starts exactly where PDF 1 ends: after Go/No-Go test passes
- Covers: Baseline → 50 % Sampling → 10 % Sampling → Tail Sampling → MCP/AI Advisor → Before/After

**Scope of TODO items:**
- Measure and record 100 % baseline (spans, errors, latency, collector resources)
- Configure and test 50 % probabilistic sampling
- Configure and test 10 % probabilistic sampling
- Configure and test tail sampling (keep errors, keep slow, sample normal)
- Confirm Prometheus metric and label names
- Build and deploy MCP Sampling Advisor container
- Verify MCP tools with MCP Inspector
- Connect AI client to MCP server and instruct it
- Review AI-generated sampling policy (human review)
- Apply AI policy to collector and redeploy
- Measure After and document Before/After delta
- Rollback and cleanup

**Status:** [ ] pending
