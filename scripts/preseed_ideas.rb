#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../app/db/sqlite"
require_relative "../app/services/memory_service"

DevMemory::DB::SQLite.init_schema!
db = DevMemory::DB::SQLite.connection
memory_service = DevMemory::Services::MemoryService.new(db: db)

PROJECT_ID = "global-dev-principles"
SCOPE = "global"

SEEDS = [
  # DHH
  {
    author: "DHH",
    memory_type: "project_convention",
    content: "Prefer convention over configuration. Defaults should keep the common path simple and fast to implement."
  },
  {
    author: "DHH",
    memory_type: "successful_pattern",
    content: "Ship integrated monoliths first. Avoid microservice splits until domain boundaries and scaling pain are proven."
  },
  {
    author: "DHH",
    memory_type: "project_convention",
    content: "Build full-stack features end-to-end with clear ownership rather than scattering logic across too many thin layers."
  },
  {
    author: "DHH",
    memory_type: "anti_pattern",
    content: "Avoid speculative abstractions. Abstract only after repeated concrete use cases emerge."
  },
  {
    author: "DHH",
    memory_type: "successful_pattern",
    content: "Use server-rendered defaults when practical; add complexity like SPAs selectively, not by default."
  },
  # Sandi Metz
  {
    author: "Sandi Metz",
    memory_type: "dev_preference",
    content: "Favor small objects with a single responsibility. Objects should expose clear intent and hide internal mechanics."
  },
  {
    author: "Sandi Metz",
    memory_type: "project_convention",
    content: "Depend on behavior, not concrete classes. Prefer messages and stable interfaces over class coupling."
  },
  {
    author: "Sandi Metz",
    memory_type: "anti_pattern",
    content: "If conditionals spread across many collaborators, refactor toward polymorphism or explicit role objects."
  },
  {
    author: "Sandi Metz",
    memory_type: "successful_pattern",
    content: "Optimize for changeability first. Code that is easy to change often ends up easier to maintain and test."
  },
  {
    author: "Sandi Metz",
    memory_type: "dev_preference",
    content: "Prefer clear naming and tiny methods over clever one-liners. Readability beats novelty."
  },
  # Andy Hunt / Dave Thomas
  {
    author: "Andy Hunt & Dave Thomas",
    memory_type: "project_convention",
    content: "Treat source code as a living product. Continuously refactor and improve instead of deferring all cleanup."
  },
  {
    author: "Andy Hunt & Dave Thomas",
    memory_type: "successful_pattern",
    content: "Automate repetitive tasks early. Build scripts and checks to preserve developer focus."
  },
  {
    author: "Andy Hunt & Dave Thomas",
    memory_type: "dev_preference",
    content: "Make decisions reversible when possible. Prefer options that reduce lock-in during early iterations."
  },
  {
    author: "Andy Hunt & Dave Thomas",
    memory_type: "project_convention",
    content: "Keep feedback loops short with tests, tooling, and frequent integration."
  },
  {
    author: "Andy Hunt & Dave Thomas",
    memory_type: "anti_pattern",
    content: "Do not duplicate knowledge across files and systems. Centralize business rules to avoid inconsistent behavior."
  },
  # Obie Fernandez
  {
    author: "Obie Fernandez",
    memory_type: "project_convention",
    content: "Use Rails conventions deeply before introducing custom framework-like layers."
  },
  {
    author: "Obie Fernandez",
    memory_type: "successful_pattern",
    content: "Keep controllers focused on orchestration; push meaningful domain behavior into models or focused services."
  },
  {
    author: "Obie Fernandez",
    memory_type: "project_convention",
    content: "Design schema and indexes intentionally. Data modeling quality drives long-term Rails maintainability."
  },
  {
    author: "Obie Fernandez",
    memory_type: "successful_pattern",
    content: "Use background jobs for slow external operations and user-visible latency reduction."
  },
  {
    author: "Obie Fernandez",
    memory_type: "anti_pattern",
    content: "Avoid overusing callbacks for complex control flow. Prefer explicit service-level orchestration when lifecycle logic grows."
  },
  # Aaron Patterson / Tenderlove
  {
    author: "Aaron Patterson",
    memory_type: "project_convention",
    content: "Measure before optimizing. Use profiling and query inspection to target true bottlenecks."
  },
  {
    author: "Aaron Patterson",
    memory_type: "successful_pattern",
    content: "Reduce object allocation churn in hot paths to improve Ruby performance and GC behavior."
  },
  {
    author: "Aaron Patterson",
    memory_type: "project_convention",
    content: "Prefer safe defaults around SQL and escaping; let framework protections work unless there is a proven need otherwise."
  },
  {
    author: "Aaron Patterson",
    memory_type: "successful_pattern",
    content: "Use eager loading and query hygiene to prevent N+1 issues in frequently accessed endpoints."
  },
  {
    author: "Aaron Patterson",
    memory_type: "anti_pattern",
    content: "Avoid opaque metaprogramming in core paths when simpler explicit code is fast enough and easier to debug."
  },
  # Martin Fowler
  {
    author: "Martin Fowler",
    memory_type: "project_convention",
    content: "Refactor continuously in small safe steps. Keep design quality improving as features evolve."
  },
  {
    author: "Martin Fowler",
    memory_type: "successful_pattern",
    content: "Use evolutionary architecture: keep high-level structure resilient to change by keeping boundaries explicit."
  },
  {
    author: "Martin Fowler",
    memory_type: "project_convention",
    content: "Model the domain language in code. Align naming with business concepts to reduce translation overhead."
  },
  {
    author: "Martin Fowler",
    memory_type: "successful_pattern",
    content: "Prefer clear test pyramids: many fast unit tests, focused integration tests, and selective end-to-end tests."
  },
  {
    author: "Martin Fowler",
    memory_type: "anti_pattern",
    content: "Do not treat patterns as mandatory templates. Use them only when they simplify a real design pressure."
  },
  # Rafael França
  {
    author: "Rafael França",
    memory_type: "project_convention",
    content: "Favor Rails APIs and conventions over framework monkey-patching; keep upgrade paths straightforward."
  },
  {
    author: "Rafael França",
    memory_type: "successful_pattern",
    content: "Prioritize backward compatibility in public APIs; deprecate gradually with clear migration guidance."
  },
  {
    author: "Rafael França",
    memory_type: "project_convention",
    content: "Keep Active Record usage explicit and predictable, especially around query behavior and lifecycle callbacks."
  },
  {
    author: "Rafael França",
    memory_type: "successful_pattern",
    content: "Improve framework-level reliability with focused regression tests before shipping behavior changes."
  },
  {
    author: "Rafael França",
    memory_type: "anti_pattern",
    content: "Avoid introducing internal framework coupling in app code that depends on private Rails internals."
  },
  # Test-Driven Development conventions
  {
    author: "TDD Conventions",
    memory_type: "project_convention",
    content: "Write a failing test first (red), implement the smallest change to pass (green), then refactor safely."
  },
  {
    author: "TDD Conventions",
    memory_type: "successful_pattern",
    content: "Keep test cycles short and focused. One behavior per test keeps failures easy to diagnose."
  },
  {
    author: "TDD Conventions",
    memory_type: "project_convention",
    content: "Use descriptive test names that state expected behavior, not internal implementation details."
  },
  {
    author: "TDD Conventions",
    memory_type: "successful_pattern",
    content: "Test public behavior and observable outcomes; avoid coupling tests to private methods."
  },
  {
    author: "TDD Conventions",
    memory_type: "anti_pattern",
    content: "Do not write broad integration tests first for small units. Start with focused unit-level behavior."
  },
  {
    author: "TDD Conventions",
    memory_type: "project_convention",
    content: "Refactor test code with the same discipline as production code to keep suites maintainable."
  },
  {
    author: "TDD Conventions",
    memory_type: "successful_pattern",
    content: "Use test doubles only at boundaries. Prefer real collaborators when they are fast and deterministic."
  },
  {
    author: "TDD Conventions",
    memory_type: "anti_pattern",
    content: "Avoid asserting too many details in one test. Overspecified tests create brittle refactors."
  },
  {
    author: "TDD Conventions",
    memory_type: "project_convention",
    content: "When fixing a bug, add a failing regression test first, then implement the fix."
  },
  {
    author: "TDD Conventions",
    memory_type: "successful_pattern",
    content: "Keep test setup explicit and minimal. Prefer factories/fixtures that emphasize intent over completeness."
  }
].freeze

def memory_exists?(db, content)
  rows = db.execute(
    "SELECT id FROM memories WHERE project_id = ? AND content = ? LIMIT 1",
    [PROJECT_ID, content]
  )
  !rows.empty?
end

inserted = 0
skipped = 0

SEEDS.each do |seed|
  if memory_exists?(db, seed[:content])
    skipped += 1
    next
  end

  memory_service.save_memory(
    content: seed[:content],
    memory_type: seed[:memory_type],
    scope: SCOPE,
    project_id: PROJECT_ID,
    confidence: 0.86,
    tags: ["seed", "principle", seed[:author].downcase.gsub(/\s+/, "_")]
  )
  inserted += 1
end

puts "Preseed complete. inserted=#{inserted} skipped=#{skipped} project_id=#{PROJECT_ID}"
