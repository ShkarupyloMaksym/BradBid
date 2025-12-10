// BradBid Exchange Configuration
// These values should be updated after Terraform deployment

const CONFIG = {
    // API Gateway Endpoints (populated after deployment)
    HTTP_API_ENDPOINT: 'https://YOUR_API_ID.execute-api.eu-central-1.amazonaws.com/prod',
    WEBSOCKET_API_ENDPOINT: 'wss://YOUR_WS_API_ID.execute-api.eu-central-1.amazonaws.com/prod',
    
    // Cognito Configuration (populated after deployment)
    COGNITO_USER_POOL_ID: 'eu-central-1_XXXXXXXXX',
    COGNITO_CLIENT_ID: 'YOUR_CLIENT_ID',
    COGNITO_DOMAIN: 'bradbid-exchange-XXXX.auth.eu-central-1.amazoncognito.com',
    
    // AWS Region
    AWS_REGION: 'eu-central-1',
    
    // Local development settings
    LOCAL_MODE: false,
    LOCAL_API_ENDPOINT: 'http://localhost:4566',
    LOCAL_WS_ENDPOINT: 'ws://localhost:4566'
};

// Use local endpoints if in development mode
if (CONFIG.LOCAL_MODE) {
    CONFIG.HTTP_API_ENDPOINT = CONFIG.LOCAL_API_ENDPOINT;
    CONFIG.WEBSOCKET_API_ENDPOINT = CONFIG.LOCAL_WS_ENDPOINT;
}
