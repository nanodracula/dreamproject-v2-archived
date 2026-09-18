# DreamApp — iOS app architecture

## Organization

- Organize files by domain concept, not by type or size. Keep feature-specific code within its feature.
- Add abstractions only when they solve an actual problem.
- Start with folder boundaries. Extract modules or packages when compiler-enforced separation provides a clear benefit.

## Layers

- **App** owns application setup, shared dependencies, and navigation between features.
- **Features** own their UI, presentation state, business logic, and feature-specific data access.
- **Core** contains shared domain models, pure business rules, and shared contracts. It remains independent of UI, persistence, and external SDKs.
- **Infrastructure** owns shared mechanisms: database connections, migrations, network transport, storage clients, and shared repository implementations.
- **SharedUI** contains domain-aware views reused across features, driven by supplied data and actions.
- **DesignSystem** contains generic UI components and visual styles, independent of domain concepts.

Features may use shared layers but never depend on each other. Shared layers never depend on features.

## Features folder

- The root screen lives directly in the feature folder. When a feature has multiple screens, each further screen gets its own folder.
- A screen's folder holds its view, its view model, and the files only that screen uses.

## UI and business logic

- Views render state and forward actions. They may own view-local interaction state. Keep persistence, networking, and non-UI platform integrations outside views.
- View models own feature presentation state, presentation logic, and operation coordination. They may call repositories directly; do not add a service merely to forward calls. Prefer `@Observable`.
- Separate presentation logic from business rules by responsibility, not complexity. Business rules belong in domain models, functions, or services within the feature or Core — not in views or view models.

## Data access

- Feature-specific queries, mappings, and repository implementations live within their feature, using shared Infrastructure mechanisms.
- Prefer reusing domain models for persistence when their shapes align without introducing storage dependencies into domain definitions. Separate models when the differences justify it.
- Prefer database observation for UI backed by local persistence. The database is authoritative for persisted data; avoid independently writable mirrors.

## Dependencies and contracts

- Inject dependencies explicitly. Avoid global singletons.
- Features assemble their internal objects using shared dependencies provided by App.
- Prefer initializer injection for business and data objects. SwiftUI environment injection is allowed for propagation within the UI.
- Prefer concrete types and direct calls. Introduce protocols when consumers need interchangeable implementations or separation from external systems.
- Keep contracts feature-local. Move them to Core when shared consumers or dependency direction require it.

---

For agents: do not change this file.