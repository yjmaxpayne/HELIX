if(NOT DEFINED HELIX_PYTHON_EXECUTABLE)
    message(FATAL_ERROR "HELIX_PYTHON_EXECUTABLE is required")
endif()

if(NOT DEFINED HELIX_PYTHON_MODULE_DIR)
    message(FATAL_ERROR "HELIX_PYTHON_MODULE_DIR is required")
endif()

set(HELIX_PYTHON_SMOKE_SCRIPT
"import helix

assert isinstance(helix.__version__, str) and helix.__version__
assert helix.runtime_version() == helix.__version__

system = helix.examples.legacy_spin_glass_system()
bath = helix.Bath.drude_lorentz_pade()
hierarchy = helix.HierarchySpec.compiled_default(bath)
options = helix.SolverOptions()
options.steps = 2

result = helix.HEOMSolver().run(system, hierarchy, options)
assert result.ok(), result.diagnostics.summary()

shape = result.reduced_density_shape
assert len(result.times) == shape.count == 1
assert shape.rows > 0 and shape.cols == shape.rows
assert result.diagnostics.backend == helix.Backend.LegacyCudaSparse
assert result.diagnostics.steps == options.steps
assert result.diagnostics.status == helix.RunStatus.Success

print(
    'helix_python_smoke: '
    f'version={helix.__version__} '
    f'times={result.times} '
    f'reduced_density_shape=({shape.count},{shape.rows},{shape.cols}) '
    f'backend={result.diagnostics.backend.name} '
    f'status={result.diagnostics.status.name}'
)
")

execute_process(
    COMMAND
        ${CMAKE_COMMAND} -E env
        "PYTHONPATH=${HELIX_PYTHON_MODULE_DIR}"
        "${HELIX_PYTHON_EXECUTABLE}" -c "${HELIX_PYTHON_SMOKE_SCRIPT}"
    RESULT_VARIABLE HELIX_PYTHON_SMOKE_RESULT
    OUTPUT_VARIABLE HELIX_PYTHON_SMOKE_OUTPUT
    ERROR_VARIABLE HELIX_PYTHON_SMOKE_ERROR
)

message(STATUS "${HELIX_PYTHON_SMOKE_OUTPUT}")

if(NOT HELIX_PYTHON_SMOKE_RESULT EQUAL 0)
    message(STATUS "${HELIX_PYTHON_SMOKE_ERROR}")
    message(FATAL_ERROR "HELIX Python smoke failed")
endif()
