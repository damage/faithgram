FROM python:3.12-slim-bookworm@sha256:34386ef0cb081344d7ec1c103ba398e6e9f64e9ab3a1509accc92a4e24a07258

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt ./
RUN python -m pip install --no-cache-dir --disable-pip-version-check -r requirements.txt
COPY server.py test_server.py ./

USER 10001:10001
EXPOSE 8787
CMD ["python", "server.py", "--host", "0.0.0.0", "--data", "/data", "--port", "8787"]
