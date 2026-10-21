document.addEventListener('DOMContentLoaded', () => {
    const video = document.getElementById('camera-video');
    const view = document.getElementById('camera-view');
    const context = view.getContext('2d');
    const startButton = document.getElementById('start-camera');
    const stopButton = document.getElementById('stop-camera');
    const cameraSelect = document.getElementById('camera-select');
    const imageInput = document.getElementById('test-image');
    const threshold = document.getElementById('confidence');
    const message = document.getElementById('camera-message');
    let stream = null;
    let generation = 0;
    let timer = null;
    let requestController = null;

    function setMessage(text, error = false) {
        message.textContent = text;
        message.classList.toggle('error', error);
    }

    function stopCamera(updateMessage = true) {
        generation += 1;
        clearTimeout(timer);
        if (requestController) requestController.abort();
        if (stream) stream.getTracks().forEach(track => track.stop());
        stream = null;
        video.srcObject = null;
        startButton.disabled = false;
        stopButton.disabled = true;
        cameraSelect.disabled = false;
        imageInput.disabled = false;
        if (updateMessage) {
            setMessage('Đã dừng camera. Kết quả trên hình là khung hình cuối.');
            document.getElementById('pet-summary').textContent = 'Camera đang tắt';
            document.getElementById('detection-list').replaceChildren();
            document.getElementById('inference-time').textContent = 'Đang chờ nhận diện';
        }
    }

    function drawDetections(result) {
        context.font = `${Math.max(18, view.width / 35)}px sans-serif`;
        context.lineWidth = Math.max(2, view.width / 300);
        for (const item of result.detections) {
            const [x1, y1, x2, y2] = item.box;
            const color = item.label === 'dog' ? '#66e6a6' : '#82c8ff';
            const label = `${item.label_vi} ${Math.round(item.confidence * 100)}%`;
            context.strokeStyle = color;
            context.strokeRect(x1, y1, x2 - x1, y2 - y1);
            const height = Math.max(28, view.width / 25);
            const top = Math.max(0, y1 - height);
            context.fillStyle = color;
            context.fillRect(x1, top, context.measureText(label).width + 14, height);
            context.fillStyle = '#101820';
            context.fillText(label, x1 + 7, top + height * 0.76);
        }
        const counts = [];
        if (result.counts.dog) counts.push(`${result.counts.dog} chó`);
        if (result.counts.cat) counts.push(`${result.counts.cat} mèo`);
        document.getElementById('pet-summary').textContent = counts.length ? `Phát hiện ${counts.join(', ')}` : 'Không phát hiện chó/mèo';
        const list = document.getElementById('detection-list');
        list.replaceChildren();
        for (const item of result.detections) {
            const row = document.createElement('li');
            const name = document.createElement('span');
            const score = document.createElement('span');
            name.textContent = item.label_vi;
            score.textContent = `${Math.round(item.confidence * 100)}%`;
            row.append(name, score);
            list.append(row);
        }
        document.getElementById('inference-time').textContent = `Suy luận: ${result.latency_ms} ms · ${result.model}`;
    }

    async function detectSource(source, width, height, currentGeneration) {
        const frame = document.createElement('canvas');
        const scale = Math.min(1, 960 / width);
        frame.width = Math.round(width * scale);
        frame.height = Math.round(height * scale);
        frame.getContext('2d').drawImage(source, 0, 0, frame.width, frame.height);
        const blob = await new Promise(resolve => frame.toBlob(resolve, 'image/jpeg', 0.85));
        if (currentGeneration !== generation) return;
        if (!blob) throw new Error('Không lấy được khung hình từ camera.');
        const form = new FormData();
        form.append('file', blob, 'camera.jpg');
        form.append('confidence', String(Number(threshold.value) / 100));
        const controller = new AbortController();
        requestController = controller;
        const timeout = setTimeout(() => controller.abort(), 90000);
        try {
            const response = await fetch('/api/detect', { method: 'POST', body: form, signal: controller.signal });
            const result = await response.json();
            if (!response.ok) throw new Error(typeof result.detail === 'string' ? result.detail : 'Dữ liệu gửi lên không hợp lệ.');
            if (currentGeneration !== generation) return;
            view.width = frame.width;
            view.height = frame.height;
            context.drawImage(frame, 0, 0);
            view.hidden = false;
            document.getElementById('camera-placeholder').hidden = true;
            drawDetections(result);
            setMessage(stream ? 'Camera đang nhận diện. Nhấn Dừng để tắt.' : 'Đã nhận diện ảnh thử.');
        } finally {
            clearTimeout(timeout);
            if (requestController === controller) requestController = null;
        }
    }

    async function cameraLoop(currentGeneration) {
        if (!stream || currentGeneration !== generation) return;
        try {
            await detectSource(video, video.videoWidth, video.videoHeight, currentGeneration);
            if (stream && currentGeneration === generation) timer = setTimeout(() => cameraLoop(currentGeneration), 250);
        } catch (error) {
            if (currentGeneration !== generation) return;
            stopCamera();
            setMessage(error.name === 'AbortError' ? 'YOLO phản hồi quá lâu. Kiểm tra terminal rồi mở camera lại.' : error.message, true);
        }
    }

    startButton.addEventListener('click', async () => {
        stopCamera(false);
        const currentGeneration = generation;
        startButton.disabled = true;
        stopButton.disabled = false;
        cameraSelect.disabled = true;
        setMessage('Đang mở camera. Hãy cho phép trình duyệt sử dụng camera.');
        try {
            if (!navigator.mediaDevices?.getUserMedia) throw new Error('Hãy mở http://localhost:8002 trên máy gắn camera.');
            const selected = cameraSelect.value;
            const openedStream = await navigator.mediaDevices.getUserMedia({
                video: selected ? { deviceId: { exact: selected }, width: { ideal: 960 }, height: { ideal: 540 } } : { width: { ideal: 960 }, height: { ideal: 540 } },
                audio: false,
            });
            if (currentGeneration !== generation) {
                openedStream.getTracks().forEach(track => track.stop());
                return;
            }
            stream = openedStream;
            video.srcObject = stream;
            await video.play();
            const devices = (await navigator.mediaDevices.enumerateDevices()).filter(device => device.kind === 'videoinput');
            if (currentGeneration !== generation) return;
            cameraSelect.replaceChildren();
            for (const [index, device] of devices.entries()) {
                cameraSelect.add(new Option(device.label || `Camera ${index + 1}`, device.deviceId));
            }
            cameraSelect.value = stream.getVideoTracks()[0].getSettings().deviceId || '';
            stream.getVideoTracks()[0].addEventListener('ended', () => {
                if (currentGeneration === generation) {
                    stopCamera();
                    setMessage('Camera đã ngắt kết nối. Kiểm tra camera rồi mở lại.', true);
                }
            });
            setMessage('Đang nhận diện khung hình đầu tiên…');
            await cameraLoop(currentGeneration);
        } catch (error) {
            if (currentGeneration !== generation) return;
            stopCamera();
            const errors = {
                NotAllowedError: 'Chưa được cấp quyền camera. Cho phép camera trên thanh địa chỉ rồi thử lại.',
                NotFoundError: 'Không tìm thấy camera. Hãy cắm webcam/USB rồi thử lại.',
                NotReadableError: 'Camera đang bận. Tắt ứng dụng khác đang sử dụng camera rồi thử lại.',
            };
            setMessage(errors[error.name] || error.message, true);
        }
    });

    stopButton.addEventListener('click', () => stopCamera());
    threshold.addEventListener('input', () => {
        document.getElementById('confidence-value').textContent = `${threshold.value}%`;
    });
    imageInput.addEventListener('change', async () => {
        const file = imageInput.files[0];
        if (!file) return;
        stopCamera(false);
        const currentGeneration = generation;
        imageInput.disabled = true;
        startButton.disabled = true;
        stopButton.disabled = false;
        setMessage('Đang nhận diện ảnh thử…');
        let image;
        try {
            image = await createImageBitmap(file);
            await detectSource(image, image.width, image.height, currentGeneration);
        } catch (error) {
            if (currentGeneration === generation) setMessage(error.name === 'AbortError' ? 'YOLO phản hồi quá lâu. Kiểm tra terminal server.' : error.message, true);
        } finally {
            image?.close();
            if (currentGeneration === generation) {
                imageInput.disabled = false;
                startButton.disabled = false;
                stopButton.disabled = true;
                imageInput.value = '';
            }
        }
    });
    window.addEventListener('pagehide', () => stopCamera());
    document.addEventListener('visibilitychange', () => { if (document.hidden) stopCamera(); });
    fetch('/api/health').then(response => {
        if (!response.ok) throw new Error('offline');
        return response.json();
    }).then(result => {
        document.getElementById('connection').textContent = `${result.model} · Sẵn sàng`;
    }).catch(() => {
        document.getElementById('connection').textContent = 'Không kết nối được YOLO';
        setMessage('Hãy chạy start-yolo.ps1 và mở http://localhost:8002.', true);
    });
});
