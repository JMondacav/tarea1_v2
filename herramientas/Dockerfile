FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gdal-bin osmium-tool postgresql-client unzip ca-certificates python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install -r /tmp/requirements.txt
ENV PATH="/opt/venv/bin:$PATH"
WORKDIR /trabajo