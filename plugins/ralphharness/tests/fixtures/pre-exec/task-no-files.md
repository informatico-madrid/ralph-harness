- [ ] 99.1 A sample task with no Files field
  - **Do**:
    1. This task tests the pre-execution critic path for tasks missing the **Files:** metadata.
    2. Since there is no **Files:** field, the coordinator derives no --paths argument.
  - **Done when**: The pre-execution critic routes this task to UNKNOWN/confirm.
  - **Verify**: `echo FIXTURE_TASK_OK`
  - **Commit**: `test(fixture): placeholder commit`
  - _Requirements: AC-2.1_
