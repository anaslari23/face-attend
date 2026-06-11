# Face Recognition Baseline

The `feat/ml-refine` scanner and recognition behavior is the current working baseline.

Do not change the face recognition flow unless the task explicitly asks for recognition changes.

Keep these areas aligned with `feat/ml-refine`:

- live face detection behavior
- face capture timing
- face size and quality thresholds
- scanner validation rules
- middleware match flow
- InsightFace matching threshold behavior
- anti-spoofing gate behavior

Allowed changes without revisiting this baseline:

- Odoo list/form display changes
- audit log column visibility
- scanner setup or token UX
- device ID logging
- non-recognition UI styling that does not change scanner state or capture behavior

If recognition becomes unreliable after a change, compare the scanner and middleware recognition paths back to `feat/ml-refine` first.
