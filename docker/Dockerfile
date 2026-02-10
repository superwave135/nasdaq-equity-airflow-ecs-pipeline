FROM apache/airflow:2.8.1-python3.11

# Set working directory
WORKDIR /opt/airflow

# Switch to root for system dependencies
USER root

# Install system dependencies needed for Great Expectations
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Switch back to airflow user for pip installs
USER airflow

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install watchtower for CloudWatch logging
RUN pip install --no-cache-dir watchtower==3.0.1

# Create directory structure for Great Expectations
RUN mkdir -p /opt/airflow/great_expectations && \
    mkdir -p /opt/airflow/scripts

# Copy Great Expectations configuration
COPY --chown=airflow:airflow great_expectations/ /opt/airflow/great_expectations/

# Copy scripts (for expectation creation and testing)
COPY --chown=airflow:airflow scripts/ /opt/airflow/scripts/

# Copy DAG files into the image
COPY --chown=airflow:airflow dags/ /opt/airflow/dags/

# Copy Airflow configuration
COPY --chown=airflow:airflow airflow.cfg /opt/airflow/airflow.cfg

# Set proper permissions
USER root
RUN chown -R airflow:root /opt/airflow/dags && \
    chmod -R 755 /opt/airflow/dags && \
    chown -R airflow:root /opt/airflow/great_expectations && \
    chmod -R 755 /opt/airflow/great_expectations && \
    chown -R airflow:root /opt/airflow/scripts && \
    chmod -R 755 /opt/airflow/scripts && \
    chown airflow:root /opt/airflow/airflow.cfg && \
    chmod 644 /opt/airflow/airflow.cfg

# Switch back to airflow user for security
USER airflow

# Set environment variables
ENV AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags
ENV AIRFLOW__CORE__LOAD_EXAMPLES=False
ENV AIRFLOW_HOME=/opt/airflow
ENV GX_DATA_CONTEXT_ROOT_DIR=/opt/airflow/great_expectations
ENV PYTHONPATH=/opt/airflow

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 \
    CMD airflow jobs check --job-type SchedulerJob --hostname "$${HOSTNAME}" || exit 1










# FROM apache/airflow:2.8.1-python3.11

# # Set working directory
# WORKDIR /opt/airflow

# # Install AWS provider and dependencies
# COPY requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt

# # Install watchtower for CloudWatch logging
# RUN pip install --no-cache-dir watchtower==3.0.1

# # Copy DAG files into the image
# COPY dags/ /opt/airflow/dags/

# # Copy Airflow configuration
# COPY airflow.cfg /opt/airflow/airflow.cfg

# # Set proper permissions
# USER root
# RUN chown -R airflow:root /opt/airflow/dags && \
#     chmod -R 755 /opt/airflow/dags && \
#     chown airflow:root /opt/airflow/airflow.cfg && \
#     chmod 644 /opt/airflow/airflow.cfg

# # Switch back to airflow user for security
# USER airflow

# # Set environment variables
# ENV AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags
# ENV AIRFLOW__CORE__LOAD_EXAMPLES=False
# ENV AIRFLOW_HOME=/opt/airflow

# # Health check
# HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 \
#     CMD airflow jobs check --job-type SchedulerJob --hostname "$${HOSTNAME}" || exit 1
