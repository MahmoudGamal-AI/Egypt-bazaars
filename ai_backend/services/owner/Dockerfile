# Use the official AWS Lambda Python 3.11 base image
FROM public.ecr.aws/lambda/python:3.11

# Set the working directory
WORKDIR ${LAMBDA_TASK_ROOT}

# Install OS-level dependencies
RUN yum update -y && \
    yum install -y \
    gcc \
    postgresql-devel \
    cargo \
    && yum clean all

# Copy the requirements file and install dependencies
COPY requirements.txt .
RUN pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt && \
    python -c "from mangum import Mangum; print('✅ mangum OK')"

# Copy the entire application code
COPY . ${LAMBDA_TASK_ROOT}/

# Set the entrypoint to the Owner handler
CMD [ "services.owner.handler.lambda_handler" ]
