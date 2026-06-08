# ====================================================
# Stage 1: Builder
# ====================================================
FROM python:3.11-slim AS builder

WORKDIR /build

# Install compilation dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy only requirements to leverage Docker cache
COPY requirements.txt .

# Install dependencies to a target folder
RUN pip install --no-cache-dir --user -r requirements.txt

# ====================================================
# Stage 2: Production
# ====================================================
FROM python:3.11-slim AS production

WORKDIR /app

# Create a non-root group and user with designated UID/GID for security
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -c "Application User" appuser

# Copy installed packages from builder stage
COPY --from=builder /root/.local /home/appuser/.local
COPY app/ app/

# Adjust environment paths to include local pip installs
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONPATH=/app

# Secure ownership of application folder
RUN chown -R appuser:appgroup /app /home/appuser

# Switch to the non-root user context
USER 10001

# Document application listening port
EXPOSE 8000

# Run FastAPI app via uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
