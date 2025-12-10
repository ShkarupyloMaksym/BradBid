"""
Integration tests for the exchange service
Note: These tests require LocalStack and Redis to be running
"""
import pytest
import json
import os
import boto3
from botocore.exceptions import ClientError

# Mark all tests in this file as integration tests
pytestmark = pytest.mark.integration


@pytest.fixture(scope="module")
def aws_clients():
    """Create AWS clients pointing to LocalStack"""
    endpoint_url = os.getenv('AWS_ENDPOINT_URL', 'http://localhost:4566')
    
    return {
        'kinesis': boto3.client('kinesis', endpoint_url=endpoint_url, region_name='us-east-1'),
        'dynamodb': boto3.client('dynamodb', endpoint_url=endpoint_url, region_name='us-east-1'),
        's3': boto3.client('s3', endpoint_url=endpoint_url, region_name='us-east-1'),
        'secretsmanager': boto3.client('secretsmanager', endpoint_url=endpoint_url, region_name='us-east-1')
    }


@pytest.fixture(scope="module")
def setup_infrastructure(aws_clients):
    """Set up test infrastructure in LocalStack"""
    # Create Kinesis streams
    try:
        aws_clients['kinesis'].create_stream(StreamName='KDS_Orders', ShardCount=1)
    except ClientError as e:
        if e.response['Error']['Code'] != 'ResourceInUseException':
            raise
    
    try:
        aws_clients['kinesis'].create_stream(StreamName='KDS_Trades', ShardCount=1)
    except ClientError as e:
        if e.response['Error']['Code'] != 'ResourceInUseException':
            raise
    
    # Create DynamoDB tables
    try:
        aws_clients['dynamodb'].create_table(
            TableName='Orders',
            AttributeDefinitions=[{'AttributeName': 'OrderId', 'AttributeType': 'S'}],
            KeySchema=[{'AttributeName': 'OrderId', 'KeyType': 'HASH'}],
            BillingMode='PAY_PER_REQUEST'
        )
    except ClientError as e:
        if e.response['Error']['Code'] != 'ResourceInUseException':
            raise
    
    try:
        aws_clients['dynamodb'].create_table(
            TableName='Trades',
            AttributeDefinitions=[{'AttributeName': 'TradeId', 'AttributeType': 'S'}],
            KeySchema=[{'AttributeName': 'TradeId', 'KeyType': 'HASH'}],
            BillingMode='PAY_PER_REQUEST'
        )
    except ClientError as e:
        if e.response['Error']['Code'] != 'ResourceInUseException':
            raise
    
    # Create S3 bucket
    try:
        aws_clients['s3'].create_bucket(Bucket='test-data-lake')
    except ClientError as e:
        if e.response['Error']['Code'] != 'BucketAlreadyOwnedByYou':
            raise
    
    # Create Secrets Manager secret
    try:
        aws_clients['secretsmanager'].create_secret(
            Name='redis-auth-token',
            SecretString=json.dumps({'auth_token': 'testpassword'})
        )
    except ClientError as e:
        if e.response['Error']['Code'] != 'ResourceExistsException':
            raise
    
    yield
    
    # Cleanup (optional - comment out to keep data for debugging)
    # aws_clients['kinesis'].delete_stream(StreamName='KDS_Orders')
    # aws_clients['kinesis'].delete_stream(StreamName='KDS_Trades')
    # aws_clients['dynamodb'].delete_table(TableName='Orders')
    # aws_clients['dynamodb'].delete_table(TableName='Trades')


@pytest.mark.integration
def test_kinesis_stream_creation(aws_clients, setup_infrastructure):
    """Test that Kinesis streams are created"""
    streams = aws_clients['kinesis'].list_streams()
    assert 'KDS_Orders' in streams['StreamNames']
    assert 'KDS_Trades' in streams['StreamNames']


@pytest.mark.integration
def test_dynamodb_table_creation(aws_clients, setup_infrastructure):
    """Test that DynamoDB tables are created"""
    tables = aws_clients['dynamodb'].list_tables()
    assert 'Orders' in tables['TableNames']
    assert 'Trades' in tables['TableNames']


@pytest.mark.integration
def test_kinesis_put_record(aws_clients, setup_infrastructure):
    """Test putting a record to Kinesis"""
    order = {
        'orderId': 'integration-test-1',
        'symbol': 'BTCUSD',
        'side': 'BUY',
        'quantity': 1.5,
        'price': 50000.0,
        'timestamp': 1234567890000
    }
    
    response = aws_clients['kinesis'].put_record(
        StreamName='KDS_Orders',
        Data=json.dumps(order),
        PartitionKey='BTCUSD-BUY'
    )
    
    assert 'SequenceNumber' in response
    assert 'ShardId' in response


@pytest.mark.integration
def test_dynamodb_put_item(aws_clients, setup_infrastructure):
    """Test putting an item to DynamoDB"""
    aws_clients['dynamodb'].put_item(
        TableName='Orders',
        Item={
            'OrderId': {'S': 'test-order-1'},
            'Symbol': {'S': 'BTCUSD'},
            'Side': {'S': 'BUY'},
            'Quantity': {'N': '1.5'},
            'Price': {'N': '50000.0'},
            'Timestamp': {'N': '1234567890000'},
            'Status': {'S': 'PENDING'}
        }
    )
    
    # Verify item was written
    response = aws_clients['dynamodb'].get_item(
        TableName='Orders',
        Key={'OrderId': {'S': 'test-order-1'}}
    )
    
    assert 'Item' in response
    assert response['Item']['Symbol']['S'] == 'BTCUSD'


@pytest.mark.integration
def test_secrets_manager_get_secret(aws_clients, setup_infrastructure):
    """Test retrieving secret from Secrets Manager"""
    response = aws_clients['secretsmanager'].get_secret_value(
        SecretId='redis-auth-token'
    )
    
    secret_data = json.loads(response['SecretString'])
    assert 'auth_token' in secret_data
    assert secret_data['auth_token'] == 'testpassword'

