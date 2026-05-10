#pragma once

namespace helix {

struct Bath;
struct ContextOptions;
struct Diagnostic;
class Context;
class Diagnostics;
struct HierarchySpec;
struct RunResult;
struct SolverOptions;
struct SparseOperator;
struct System;
class HEOMSolver;

namespace examples {
System legacy_spin_glass_system();
}

} // namespace helix
