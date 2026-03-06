FROM cgr.dev/chainguard/python:latest
WORKDIR /app
COPY app.py .
CMD ["app.py"]