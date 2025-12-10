# BradBid

BradBid: A real-time serverless auction system on AWS, developed by the Sigmoindus student team for the BDIT4DA Big Data course.

## Architecture

Architecture plan (SQS/Free Tier edition) is documented in `docs/aws-sqs-architecture.tex` (LuaLaTeX).

### Components

- **Frontend**: React/Vanilla JS SPA hosted on S3/CloudFront
- **Authentication**: AWS Cognito User Pool
- **API Gateway**: HTTP API for REST, WebSocket API for real-time updates
- **Lambda Functions**:
  - `Ingest`: Handles POST /orders, validates and queues orders
  - `Matcher`: Processes orders from SQS, matches trades using Redis order book
  - `WSHandler`: Manages WebSocket connections
  - `TradeBroadcaster`: Broadcasts trade updates to connected clients
- **Queues**: SQS FIFO (orders.fifo, trades.fifo)
- **Storage**: DynamoDB (Orders, Trades, WSConnections), S3 (analytics, SPA)
- **Cache**: ElastiCache Redis for order book
- **Analytics**: Kinesis Firehose → S3 → Glue → Athena

## Project Structure

```
/infra          # Terraform infrastructure
/backend        # Lambda functions (Python)
/frontend       # SPA (HTML/CSS/JS)
/docs           # Documentation (LaTeX)
/scripts        # Helper scripts
/.github        # CI/CD workflows
```

## Getting Started

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.6.0
- Python >= 3.9
- Docker & Docker Compose (for local development)

### Local Development

1. Start LocalStack and Redis:
```bash
docker-compose up -d
```

2. Set up local resources:
```bash
chmod +x scripts/setup-localstack.sh
./scripts/setup-localstack.sh
```

3. Run tests:
```bash
cd backend
pip install -r requirements.txt
pip install pytest
pytest tests/ -v
```

### Deployment

1. Initialize Terraform:
```bash
cd infra
terraform init
```

2. Plan and apply:
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

3. Update frontend config with output values from Terraform.

4. Deploy frontend to S3:
```bash
aws s3 sync frontend/src/ s3://<spa-bucket-name>/
```

### Destroy Resources

To save costs, destroy all resources when not in use:
```bash
cd infra
terraform destroy
```

Or use the GitHub Actions "Destroy Infrastructure" workflow.

## CI/CD

GitHub Actions workflows:
- `deploy.yml`: Validates, tests, and deploys on push to main
- `destroy.yml`: Manual workflow to destroy all resources

Required secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Cost Optimization

This project is designed to run within AWS Free Tier:
- SQS instead of Kinesis Data Streams
- Public subnets only (no NAT Gateway)
- ElastiCache t3.micro
- On-demand pricing for DynamoDB
- S3 lifecycle rules for analytics data

## Team

**Participant A (Infrastructure + Frontend)**:
- VPC, CloudFront, Route 53
- Cognito configuration
- SPA development

**Participant B (Backend + Data Pipeline)**:
- SQS, DynamoDB setup
- Lambda functions
- Redis, Analytics layer
- CloudWatch monitoring

## License

See [LICENSE](LICENSE) file.
