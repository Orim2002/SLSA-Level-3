FROM gcr.io/distroless/python3-debian12:nonroot
WORKDIR /app
COPY app.py .
CMD ["app.py"]