# Demos

This folder holds shared demo artifacts that span multiple lessons — for example, the hub-and-spoke baseline network used across Lessons 5, 6, 7, and 12.

Lesson-specific demos live inside `lessons/lesson-NN-slug/demos/`.

## Conventions

- **Idempotent.** Every script can be run twice in a row without errors.
- **Self-cleaning.** Every script ends with a teardown block (commented out by default).
- **Parameterized.** Sandbox names, regions, and pricing tiers sit in a header block at the top.
- **Cross-tool parity.** Where reasonable, each demo ships with Azure CLI (`az`), Azure PowerShell (`Az`), and Bicep equivalents.
