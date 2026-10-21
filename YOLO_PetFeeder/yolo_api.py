"""Standalone YOLO webcam and dog/cat detection API for PetFeeder."""
from __future__ import annotations

import io
import logging
import os
import threading
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageOps, UnidentifiedImageError
from starlette.concurrency import run_in_threadpool

PROJECT_ROOT = Path(__file__).resolve().parent
WEB_ROOT = PROJECT_ROOT / "web"
MODEL_PATH = PROJECT_ROOT / "models" / "yolo11n.pt"
MAX_IMAGE_BYTES = 8 * 1024 * 1024
RESULT_TTL_SECONDS = 3.0
PET_CLASSES = {15: ("cat", "Mèo"), 16: ("dog", "Chó")}
INFERENCE_LOCK = threading.Lock()
STATE_LOCK = threading.Lock()
detector = None
latest_result = None
latest_frame_time = None
logger = logging.getLogger("uvicorn.error")


def load_detector():
    global detector
    if detector is None:
        from ultralytics import YOLO

        detector = YOLO(str(MODEL_PATH))
    return detector


def warmup_detector():
    load_detector().predict(
        source=Image.new("RGB", (640, 480)),
        classes=list(PET_CLASSES),
        conf=0.5,
        imgsz=640,
        device=os.getenv("YOLO_DEVICE", "cpu"),
        verbose=False,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Loading YOLO11n...")
    await run_in_threadpool(load_detector)
    logger.info("Warming up YOLO before accepting camera frames...")
    await run_in_threadpool(warmup_detector)
    yield


app = FastAPI(title="PetFeeder YOLO Camera", version="1.0.0", lifespan=lifespan)
app.mount("/web", StaticFiles(directory=str(WEB_ROOT)), name="web")


@app.get("/", include_in_schema=False)
def camera_page():
    return FileResponse(WEB_ROOT / "yolo-camera.html")


@app.get("/api/health")
def health():
    return {"success": True, "model": MODEL_PATH.name, "model_loaded": detector is not None}


def detect_image(contents: bytes, confidence: float) -> dict:
    global latest_result, latest_frame_time
    if not contents or len(contents) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "Ảnh phải có dữ liệu và nhỏ hơn hoặc bằng 8 MB.")
    # Timestamp the submitted frame, so slow inference cannot make an old image fresh.
    frame_time = time.monotonic()
    try:
        with Image.open(io.BytesIO(contents)) as source:
            if source.width * source.height > 20_000_000:
                raise HTTPException(413, "Ảnh vượt quá 20 triệu pixel.")
            image = ImageOps.exif_transpose(source).convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise HTTPException(400, "Không đọc được ảnh. Hãy gửi ảnh JPEG/PNG hợp lệ.") from exc

    with INFERENCE_LOCK:
        started = time.perf_counter()
        try:
            result = load_detector().predict(
                source=image,
                classes=list(PET_CLASSES),
                conf=confidence,
                imgsz=640,
                device=os.getenv("YOLO_DEVICE", "cpu"),
                verbose=False,
            )[0]
        except Exception as exc:
            logger.exception("YOLO inference failed")
            raise HTTPException(500, "YOLO không chạy được. Xem lỗi trong terminal server.") from exc

        detections = []
        for box in result.boxes:
            class_id = int(box.cls.item())
            if class_id not in PET_CLASSES:
                continue
            label, label_vi = PET_CLASSES[class_id]
            detections.append({
                "label": label,
                "label_vi": label_vi,
                "confidence": round(float(box.conf.item()), 4),
                "box": [round(float(value), 1) for value in box.xyxy[0].tolist()],
            })
        counts = {label: sum(item["label"] == label for item in detections) for label in ("cat", "dog")}
        present_classes = [label for label, count in counts.items() if count]
        payload = {
            "success": True,
            "model": MODEL_PATH.name,
            "pet_detected": bool(detections),
            "pet_type": present_classes[0] if len(present_classes) == 1 else None,
            "counts": counts,
            "detections": detections,
            "image_width": image.width,
            "image_height": image.height,
            "latency_ms": round((time.perf_counter() - started) * 1000, 1),
            "captured_at": datetime.now(timezone.utc).isoformat(),
        }
        with STATE_LOCK:
            if latest_frame_time is None or frame_time >= latest_frame_time:
                latest_result = payload
                latest_frame_time = frame_time
    return payload


@app.post("/api/detect")
def detect(file: UploadFile = File(...), confidence: float = Form(0.5, ge=0.1, le=1.0)):
    """Upload a webcam frame as multipart/form-data; boxes are [x1, y1, x2, y2]."""
    try:
        contents = file.file.read(MAX_IMAGE_BYTES + 1)
    finally:
        file.file.close()
    return detect_image(contents, confidence)


@app.get("/api/status")
def status():
    """Latest observation for IoT consumers. Old/missing observations report no pet."""
    with STATE_LOCK:
        age_ms = None if latest_frame_time is None else round((time.monotonic() - latest_frame_time) * 1000)
        fresh = age_ms is not None and age_ms < RESULT_TTL_SECONDS * 1000
        result = latest_result if fresh else None
        return {
            "success": True,
            "fresh": fresh,
            "age_ms": age_ms,
            "ttl_ms": int(RESULT_TTL_SECONDS * 1000),
            "pet_detected": bool(result and result["pet_detected"]),
            "pet_type": result["pet_type"] if result else None,
            "counts": result["counts"] if result else {"cat": 0, "dog": 0},
            "detections": result["detections"] if result else [],
        }


if __name__ == "__main__":
    uvicorn.run(app, host=os.getenv("YOLO_HOST", "127.0.0.1"), port=int(os.getenv("YOLO_PORT", "8002")))
