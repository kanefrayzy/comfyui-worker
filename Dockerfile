# ============================================================
#  Custom worker-comfyui для epiCRealism XL + PuLID v1.1 + LoRA + FaceDetailer
#  База: официальный RunPod worker-comfyui (clean, без моделей)
#  Модели подключаются с Network Volume (см. endpoint config).
#  Кастомные ноды и зависимости — запечены в образ.
# ============================================================
FROM runpod/worker-comfyui:5.8.5-base

# --- системные пакеты (на случай сборки insightface/onnx) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget libgl1 libglib2.0-0 unzip \
 && rm -rf /var/lib/apt/lists/*

# --- Python-зависимости кастомных нод ---
# (те самые, что мы ставили руками на Pod: insightface, timm, ftfy, facexlib, filterpy, onnxruntime-gpu, ultralytics)
RUN pip install --no-cache-dir \
    insightface \
    timm \
    ftfy \
    facexlib \
    filterpy \
    onnxruntime-gpu \
    ultralytics

# --- Кастомные ноды ---
WORKDIR /comfyui/custom_nodes

# PuLID v1.1 (форк vitrun, ветка feature/v1.1 — поддержка ip-adapter_pulidv1.1)
RUN git clone -b feature/v1.1 https://github.com/vitrun/PuLID_ComfyUI.git && \
    pip install --no-cache-dir -r PuLID_ComfyUI/requirements.txt || true

# Impact-Pack (FaceDetailer)
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    pip install --no-cache-dir -r ComfyUI-Impact-Pack/requirements.txt || true

# Impact-Subpack (UltralyticsDetectorProvider)
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git && \
    pip install --no-cache-dir -r ComfyUI-Impact-Subpack/requirements.txt || true

# --- Симлинки для папок, которые кастомные ноды ищут в /comfyui/models/ ---
# PuLID и Impact-Subpack (ultralytics) НЕ читают extra_model_paths — они смотрят
# жёстко в /comfyui/models/{pulid,ultralytics,insightface}. Линкуем их на volume.
# Симлинк создаётся при сборке, резолвится при обращении уже на работающем воркере
# (где /runpod-volume примонтирован).
RUN rm -rf /comfyui/models/pulid /comfyui/models/ultralytics /comfyui/models/insightface && \
    ln -s /runpod-volume/models/pulid       /comfyui/models/pulid && \
    ln -s /runpod-volume/models/ultralytics /comfyui/models/ultralytics && \
    ln -s /runpod-volume/models/insightface /comfyui/models/insightface

# --- EVA-CLIP: запекаем в образ, чтобы PuLID не качал его на холодном старте ---
# PuLID грузит EVA02-CLIP-L-14-336 через open_clip / HF Hub. Прогреваем кэш при сборке.
RUN python -c "from huggingface_hub import hf_hub_download; \
hf_hub_download(repo_id='QuanSun/EVA-CLIP', filename='EVA02_CLIP_L_336_psz14_s6B.pt')" || \
    echo 'WARN: EVA-CLIP prefetch failed, will download at runtime'

# вернуться в рабочую папку воркера
WORKDIR /

# worker-comfyui сам стартует ComfyUI + RunPod handler через свой entrypoint.
# CMD наследуется из базового образа — переопределять не нужно.
