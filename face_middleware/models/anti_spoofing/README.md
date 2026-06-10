This folder stores the production passive anti-spoofing model.

With `FACE_MIDDLEWARE_ANTI_SPOOFING_ENABLED=true` and
`FACE_MIDDLEWARE_ALLOW_ANTISPOOF_STUB=false`, `/match` and `/match/faces` fail
closed until a model is present and loadable.

The default local setup uses Silent-Face MiniFASNet weights under
`silent_face/`. ONNX models are also supported by pointing
`FACE_MIDDLEWARE_ANTISPOOF_MODEL_PATH` at an `.onnx` file.

Avatar registration through `/register` does not use anti-spoofing because
Odoo avatars are stored photos.
