---
trigger: glob
globs: /humanizer
name: code-review-and-quality
description: Reviews and improves existing code for correctness, natural human-written readability, architecture, security, and performance while preserving its current behavior and public interfaces. Use before merging changes, after implementation or bug fixes, during refactoring, or when reviewing a diff or pull request.
---

# Code Review and Quality

## Purpose
Improve code health without changing what the software does unless the task explicitly asks for new behavior. Prefer code that a capable engineer would naturally write: clear names, direct control flow, familiar project conventions, and abstractions that solve a real problem.

Every review covers five areas:

Correctness and behavior preservation
Readability and maintainability
Architecture and design
Security
Performance and resource use
Approval standard: Approve changes that measurably or clearly improve overall code health. Do not demand personal stylistic preferences. Do not block useful improvements because the code is not perfect.

When to Use
Before merging a pull request or change
After implementing a feature or fixing a bug
When reviewing code written by a person or another model
When refactoring existing code
When performance, reliability, or maintainability needs improvement
Core Rule: Preserve Behavior First
When modifying existing code, treat current behavior as the baseline.

Preserve existing features, business rules, output formats, side effects, error behavior, and public APIs unless the task explicitly authorizes a change.
Before editing, identify the entry points, callers, important invariants, dependencies, and tests.
Prefer small, targeted changes over rewriting a working system from scratch.
Do not remove features or simplify away edge cases just to make code shorter.
If behavior is ambiguous, inspect tests and call sites. Ask a focused question only when the uncertainty materially affects the result.
When a behavior change is necessary, state what changes and why.
Do not claim behavior is preserved or performance improved unless checks or evidence support the claim.
The Five-Axis Review
1. Correctness and Regression Risk
Check whether the code does what the requirements and existing callers expect.

Match the specification and intended behavior.
Inspect null, empty, invalid, boundary, and unusually large inputs.
Check error handling, resource cleanup, concurrency, state transitions, and race conditions.
Verify that tests assert observable behavior rather than implementation details.
Look for off-by-one errors, swallowed exceptions, incorrect defaults, and unintended side effects.
Add or update regression tests for every meaningful bug fix.
Preserve compatibility with existing callers and data.
2. Human-Readable Code
Make code feel natural to read and maintain—not artificially “humanized.”

Use descriptive, domain-appropriate names that match the repository's conventions.
Prefer straightforward control flow over clever tricks, nested ternaries, unnecessary callbacks, or deeply nested branches.
Group related logic and give functions one clear responsibility.
Keep comments for intent, constraints, and non-obvious decisions; do not narrate obvious code.
Avoid mechanical rewrites that only change variable names or formatting without improving comprehension.
Avoid both extremes: cryptic one-liners and verbose, line-by-line ceremony.
Remove unnecessary wrappers, redundant conditions, dead assignments, and duplicated logic when safe.
Keep abstractions only when they reduce duplication or make a concept easier to understand.
Do not force every function into the same shape. Follow the language and project's idioms.
Do not add fake personal touches, inconsistent formatting, or needless comments to make code appear human-written.
Readability test: Can another engineer understand the purpose, important decisions, and failure paths without asking the original author?

3. Architecture and Simplicity
Check whether responsibilities and dependencies are placed appropriately.

Follow established project patterns unless there is a concrete reason to change them.
Keep module boundaries clear and dependencies flowing in the correct direction.
Reuse the canonical helper or service instead of creating a near-duplicate.
Keep feature-specific behavior in the layer that owns it.
Replace repeated conditional logic with a clear dispatcher or model only when it simplifies the design.
Separate orchestration from business logic when doing so makes each easier to understand or test.
Make type and data boundaries explicit. Avoid unnecessary casts, overly broad types, and silent fallbacks that hide invalid states.
Do not over-engineer one-off needs. Introduce general abstractions only when they pay for their complexity.
Prefer removing unnecessary concepts and branches over moving the same complexity into new files or wrappers.
Consider file size as a signal, not a rigid rule. If a file is approaching roughly 1,000 lines and a change would grow it substantially, consider extracting cohesive modules first.
4. Security and Robustness
Check whether the change introduces or preserves avoidable risks.

Validate untrusted input at system boundaries.
Keep secrets, credentials, and personal data out of source code and logs.
Verify authentication and authorization where required.
Use parameterized database queries and safe output encoding.
Handle external API responses, files, configuration, and user content as untrusted.
Check dependency provenance and known vulnerabilities when relevant.
Avoid unsafe deserialization, path traversal, command injection, and accidental data exposure.
Follow the project's existing security guidance. For detailed hardening, use the security-and-hardening skill when available.
5. Performance
Optimize real bottlenecks without sacrificing correctness or clarity.

Look for N+1 queries, repeated expensive work, unnecessary allocations, unbounded loops, and unbounded data fetching.
Check for synchronous I/O in latency-sensitive paths and unnecessary work on the main thread.
Inspect UI re-renders, repeated computations, cache behavior, and pagination where relevant.
Reuse computed values when doing so is simpler and correct; do not add caches without a clear invalidation strategy.
Prefer suitable algorithms and data structures when input size makes the difference meaningful.
Reduce network calls, database round trips, serialization overhead, and memory copies where practical.
Avoid premature micro-optimizations and obscure low-level tricks that make maintenance harder.
Use profiling, benchmarks, query plans, or measurements for performance-sensitive changes when possible.
Compare before and after using the same workload. If measurement is unavailable, label the improvement as a hypothesis rather than a verified result.
For deeper profiling, use the performance-optimization skill when available.
Preferred Structural Improvements
When identifying a structural problem, recommend a concrete fix rather than only describing the problem.

Replace a long conditional chain with a small, explicit dispatcher when it clarifies the cases.
Merge duplicate branches into one shared flow when their behavior is genuinely the same.
Separate coordination code from domain logic when it improves testing and comprehension.
Move feature-specific logic into the module that owns that feature.
Reuse an established helper rather than maintaining a second implementation.
Make an unclear type or input boundary explicit.
Delete pass-through wrappers that add indirection but no value.
Extract a helper or module when it creates a clear responsibility boundary.
Prefer the smallest structural change that removes complexity.
Review Workflow
Step 1: Understand the Change
Before editing or reviewing, establish:

What the change is intended to achieve
The expected behavior before and after
Which public interfaces and callers must remain compatible
The relevant project conventions, tests, and constraints
Do not infer a new requirement from personal preference.

Step 2: Inspect Tests and Existing Behavior
Find the relevant tests and determine which behaviors they protect.
Check whether important edge cases are missing.
Read the implementation and its callers to understand implicit contracts.
If practical, run the existing tests before editing to establish a baseline.
If no tests exist, identify the most important observable behaviors to test.
Tests reveal intent, but do not assume the tests themselves are complete or correct.

Step 3: Make a Focused Improvement
Keep the change focused on one logical goal.
Preserve existing behavior and public interfaces.
Prefer small refactors that are easy to verify and review.
Do not mix unrelated feature work with refactoring.
Avoid broad rewrites unless the current structure prevents a safe, meaningful improvement.
Update tests and documentation only where the change requires it.
Step 4: Verify the Result
Run the most relevant checks available:

Unit and regression tests
Type checks, linting, and formatting checks
Build or compilation
Integration or manual tests where appropriate
Benchmarks or profiling for performance claims
Review the final diff for accidental changes, missing error handling, newly unused code, and unrelated formatting churn.

Never claim a check passed if it was not run. If a check cannot be run, say so clearly.

For critical conditionals, a mutation test can help validate test quality: temporarily invert or alter the condition, confirm the relevant test fails, and restore the original implementation. Do this only in a safe, reversible environment.

Step 5: Report Findings by Severity
Use these labels consistently:

Label	Meaning	Expected action
Critical	Severe security issue, data loss, or broken core functionality	Must fix before merge
Required	Correctness, compatibility, security, or material maintainability issue	Fix before merge
Optional	Useful improvement that is not required for correctness	Consider
Nit	Minor style preference with little impact	Optional
FYI	Relevant information without a requested action	No action required
Lead with the highest-impact issues: correctness and security first, then behavior regressions, architecture, performance, and cosmetic concerns. A few well-supported findings are better than a long list of speculative nits.

For each finding, include:

Severity
File and location when available
The concrete problem and its impact
A specific, proportionate remedy
Step 6: Check for Dead Code
After a refactor or implementation change:

Identify code that is now unreachable, unused, or redundant.
Confirm it is not used through reflection, dynamic registration, configuration, or external callers.
List uncertain removals explicitly.
Ask before deleting questionable elements.
Do not leave confirmed dead code behind, but do not silently delete code whose role is unclear.

Change Size and Reviewability
Prefer focused, reviewable diffs.

Around 100 changed lines: usually easy to review.
Around 300 changed lines: acceptable for one coherent change.
Around 1,000 changed lines: usually split into smaller changes unless it is a mechanical transformation or complete deletion.
These are guidelines, not hard limits. A small diff can still create architectural complexity, and a large mechanical change can be straightforward to verify.

When a change is too large, split it by dependency, file group, or end-to-end feature slice. Establish shared interfaces before changing their consumers when necessary.

Change Descriptions
Use a first line that is short, imperative, and specific—for example, “Preserve cache behavior during request refactoring.”

Explain:

What changed
Why it changed
Any important trade-offs or limitations
Tests and benchmarks run
Any known follow-up work
Avoid vague descriptions such as “Fix stuff,” “Improve code,” or “Phase 1.”

Multi-Perspective Review
For high-risk changes, use separate implementation and review perspectives when pract