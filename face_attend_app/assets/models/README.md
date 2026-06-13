Production phone-only face matching uses the InsightFace ArcFace model:

- `w600k_r50.onnx`

The Android app runs this model through ONNX Runtime after MediaPipe/BlazeFace
face detection and InsightFace-compatible 112x112 five-point alignment.
