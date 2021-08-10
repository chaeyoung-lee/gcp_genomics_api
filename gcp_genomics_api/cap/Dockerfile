FROM python:3

# Install gsutil
RUN apt-get update && \
    apt-get install -y \
        curl \
        python-pip \
        gcc \
        lsb-release && \
    export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" && \
    echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    apt-get update && apt-get install -y google-cloud-sdk && \
    pip install crcmod


WORKDIR /root
ADD cap.py cap.py
RUN mkdir -p input output

CMD ["python", "/root/cap.py", "1"]