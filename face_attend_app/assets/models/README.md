Place the production face-embedding TFLite model here, for example:

- `mobilefacenet.tflite`

The current Flutter service exposes the embedding boundary and includes a deterministic
development fallback so the API and UI can be tested before the model artifact is added.
