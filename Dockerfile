# syntax=docker/dockerfile:1.7

ARG PYTHON_VERSION=3.10
FROM python:${PYTHON_VERSION}-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_DEFAULT_TIMEOUT=120

# System dependencies for scientific/python audio/video stack
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        bash-completion \
        git \
        curl \
        ca-certificates \
        ffmpeg \
        gnupg \
        iproute2 \
        iputils-ping \
        libasound2 \
        libasound2-dev \
        libegl1 \
        libgl1 \
        libglib2.0-0 \
        libgtk2.0-0 \
        libjpeg62-turbo-dev \
        libopenblas-dev \
        libportaudio2 \
        libsndfile1 \
        libsm6 \
        libssl3 \
        libxext6 \
        libxrender1 \
        nano \
        net-tools \
        openssh-client \
        portaudio19-dev \
        pulseaudio-utils \
        pkg-config \
        libsdl2-2.0-0 \
        libsdl2-image-2.0-0 \
        libsdl2-mixer-2.0-0 \
        libsdl2-ttf-2.0-0 \
        ripgrep \
        rsync \
        sudo \
        espeak-ng \
        libespeak-ng1 \
        unzip \
        vim \
        wget \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip and install shared Python dependencies.
# Packages that are Pi-specific are substituted with mocks later.
RUN pip install --upgrade pip \
    && pip install \
        eventlet \
        flask \
        flask-socketio \
        gunicorn \
        numpy \
        opencv-python \
        mediapipe \
        paho-mqtt \
        pillow \
        protobuf \
        pyaudio \
        pydub \
        pygame \
        pyttsx3 \
        requests \
        soundfile \
        tqdm \
        urllib3 \
        vosk \
        websockets \
        edge-tts \
        fake-rpi

# Create non-root user aligned with host (customisable via build args)
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN if ! getent group "${USER_GID}" >/dev/null; then \
        groupadd --gid "${USER_GID}" "${USERNAME}"; \
    else \
        groupname="$(getent group ${USER_GID} | cut -d: -f1)"; \
        if [ "$groupname" != "${USERNAME}" ]; then \
            groupmod --new-name "${USERNAME}" "$groupname"; \
        fi; \
    fi \
    && if ! id -u "${USER_UID}" >/dev/null 2>&1; then \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" -m "${USERNAME}" -s /bin/bash; \
    else \
        username="$(getent passwd ${USER_UID} | cut -d: -f1)"; \
        if [ "$username" != "${USERNAME}" ]; then \
            usermod -l "${USERNAME}" "$username"; \
        fi; \
        usermod -d "/home/${USERNAME}" "${USERNAME}"; \
    fi \
    && usermod -aG audio,video "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Provide lightweight stub implementations for Pi-only libraries so code可以在容器中模拟硬件。
RUN mkdir -p /opt/xgo-stubs/xgolib /opt/xgo-stubs/xgoscreen

RUN cat <<'PY' > /opt/xgo-stubs/xgolib/__init__.py
import types
import warnings


class _StubMethod:
    def __init__(self, name):
        self._name = name

    def __call__(self, *args, **kwargs):
        warnings.warn(f"[xgolib stub] {self._name} called with args={args}, kwargs={kwargs}")
        if self._name == "read_battery":
            return 100
        if self._name == "read_firmware":
            return "SIM-FW"
        if self._name == "read_lib_version":
            return "SIM-LIB"
        if self._name == "read_joint_status":
            return [{"id": 0, "angle": 0.0}]
        return None


class XGO:
    def __init__(self, port="/dev/ttyAMA0", version="xgolite"):
        warnings.warn(
            "[xgolib stub] Using simulated XGO interface "
            f"(port={port}, version={version}). Real hardware is not available."
        )
        self.port = port
        self.version = version

    def __getattr__(self, item):
        return _StubMethod(item)


__all__ = ["XGO"]
PY

RUN cat <<'PY' > /opt/xgo-stubs/xgoscreen/__init__.py
__all__ = ["LCD_2inch"]
PY

RUN cat <<'PY' > /opt/xgo-stubs/xgoscreen/LCD_2inch.py
import warnings


class LCD_2inch:
    def __init__(self, *_, width=320, height=240, **__):
        warnings.warn("[xgoscreen stub] 2-inch LCD display using simulated backend.")
        self.width = width
        self.height = height

    def Init(self):
        warnings.warn("[xgoscreen stub] Init called.")

    def clear(self):
        warnings.warn("[xgoscreen stub] clear called.")

    def ShowImage(self, *_):
        warnings.warn("[xgoscreen stub] ShowImage called (no-op).")
PY

# Ensure stub modules are importable ahead of site-packages.
ENV PYTHONPATH="/opt/xgo-stubs:${PYTHONPATH}"

# Convenience scripts for development workflow
RUN cat <<'BASH' >/usr/local/bin/xgo-disable-stubs
#!/bin/bash
# Remove XGO stub path from PYTHONPATH for commands that need real hardware libs.
_filtered=""
IFS=':' read -ra _paths <<<"${PYTHONPATH}"
for _p in "${_paths[@]}"; do
    [ -z "${_p}" ] && continue
    if [ "${_p}" != "/opt/xgo-stubs" ]; then
        if [ -z "${_filtered}" ]; then
            _filtered="${_p}"
        else
            _filtered="${_filtered}:${_p}"
        fi
    fi
done
export PYTHONPATH="${_filtered}"
exec "$@"
BASH

RUN cat <<'BASH' >/usr/local/bin/install-xgo-extras
#!/bin/bash
set -euo pipefail
REQ_FILE="${1:-/workspace/RaspberryPi-CM4-main/demos/xiaozhi_test/requirements.txt}"
if [ ! -f "${REQ_FILE}" ]; then
    echo "Requirement file not found: ${REQ_FILE}" >&2
    exit 1
fi
echo "[install-xgo-extras] Installing dependencies from ${REQ_FILE}"
python - "${REQ_FILE}" <<'PY' >/tmp/xgo_extra_requirements.txt
import sys
import pathlib
req = pathlib.Path(sys.argv[1]).read_text().splitlines()
skip_prefixes = (
    "PyQt-", "PyQt5", "pycaw", "comtypes", "pynput", "pyperclip"
)
for line in req:
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith(skip_prefixes):
        continue
    print(line)
PY
pip install --upgrade pip
pip install -r /tmp/xgo_extra_requirements.txt
echo "[install-xgo-extras] Done."
BASH

RUN chmod +x /usr/local/bin/xgo-disable-stubs /usr/local/bin/install-xgo-extras

# Shell convenience for the dev user
RUN echo ". /etc/profile" >> /etc/skel/.bashrc && \
    echo "source /usr/share/bash-completion/bash_completion" >> /etc/skel/.bashrc && \
    echo "export PYTHONPATH=/opt/xgo-stubs:\$PYTHONPATH" >> /etc/skel/.bashrc && \
    cp /etc/skel/.bashrc /home/${USERNAME}/.bashrc && \
    chown ${USER_UID}:${USER_GID} /home/${USERNAME}/.bashrc

# Default workspace mirrors project root on the host.
WORKDIR /workspace
RUN chown ${USER_UID}:${USER_GID} /workspace

# Expose common dev ports (Flask + MJPEG stream) for convenience.
EXPOSE 80 5000 5001

# Switch to the non-root user by default.
USER ${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

# Provide helpful default command.
CMD ["bash"]
