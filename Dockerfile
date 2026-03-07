# Stage 1: Build
FROM cgr.dev/chainguard/python:latest-dev AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

# Stage 2: Runtime
FROM cgr.dev/chainguard/python:latest
WORKDIR /app

# Copy installed packages from the builder stage
COPY --from=builder /home/nonroot/.local /home/nonroot/.local
COPY app.py .

# Update PATH to include local bin
ENV PATH=$PATH:/home/nonroot/.local/bin

ENTRYPOINT ["python", "app.py"]