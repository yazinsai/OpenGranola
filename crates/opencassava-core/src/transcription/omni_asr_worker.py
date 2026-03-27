import json
import os
import sys
import numpy as np
import soundfile as sf
import tempfile

MODELS = {}

def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()

def handle_health():
    emit({"ok": True, "result": {"status": "ready"}})

def handle_ensure_model(payload):
    model_name = payload["model"]
    device = payload.get("device", "auto")
    
    if model_name not in MODELS:
        from omnilingual_asr.pipelines import ASRInferencePipeline
        # We assume the library handles device placement or we can pass it if supported
        pipeline = ASRInferencePipeline.from_pretrained(model_name)
        MODELS[model_name] = pipeline
        
    emit({"ok": True, "result": {"model": model_name}})

def handle_transcribe(payload):
    model_name = payload["model"]
    samples = np.asarray(payload.get("samples", []), dtype=np.float32)
    
    if model_name not in MODELS:
        from omnilingual_asr.pipelines import ASRInferencePipeline
        pipeline = ASRInferencePipeline.from_pretrained(model_name)
        MODELS[model_name] = pipeline
    else:
        pipeline = MODELS[model_name]
    
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            tmp_path = f.name
        sf.write(tmp_path, samples, 16000)
        
        # omnilingual-asr typically takes a file path
        result = pipeline(tmp_path)
        # Assuming result is a string or has a text attribute based on typical pipeline behavior
        text = str(result).strip()
        emit({"ok": True, "result": {"text": text}})
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)

def main():
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue

        try:
            payload = json.loads(line)
            command = payload.get("command")
            if command == "health":
                handle_health()
            elif command == "ensure_model":
                handle_ensure_model(payload)
            elif command == "transcribe":
                handle_transcribe(payload)
            elif command == "shutdown":
                emit({"ok": True, "result": {"shutdown": True}})
                return
            else:
                emit({"ok": False, "error": f"Unknown command: {command}"})
        except Exception as exc:
            emit({"ok": False, "error": str(exc)})

if __name__ == "__main__":
    main()
