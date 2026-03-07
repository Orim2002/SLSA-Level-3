FROM cgr.dev/chainguard/python:latest-dev@sha256:7c5b6cdd6900ee7e44cb86e28f2cb8f7cf73a1943e5d094fe9b9cc84ab2f3ca5 AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM cgr.dev/chainguard/python:latest@sha256:7ca65e0945567fe07eebbd0dfc34486938b02a79b4851b2675b899599e2e659e
WORKDIR /app

COPY --from=builder /home/nonroot/.local /home/nonroot/.local
COPY app.py .

ENV PATH=$PATH:/home/nonroot/.local/bin

ENTRYPOINT ["python", "app.py"]