// BradBid Exchange Frontend Application

let websocket = null;
let authToken = null;
let reconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = 10;
const BASE_RECONNECT_DELAY = 1000; // 1 second

// Initialize the application
document.addEventListener('DOMContentLoaded', () => {
    initializeWebSocket();
    loadMockOrderBook();
});

// Calculate reconnection delay with exponential backoff and jitter
function getReconnectDelay() {
    const exponentialDelay = Math.min(BASE_RECONNECT_DELAY * Math.pow(2, reconnectAttempts), 30000);
    const jitter = Math.random() * 1000; // Add up to 1 second of random jitter
    return exponentialDelay + jitter;
}

// WebSocket Connection
function initializeWebSocket() {
    try {
        websocket = new WebSocket(CONFIG.WEBSOCKET_API_ENDPOINT);
        
        websocket.onopen = () => {
            console.log('WebSocket connected');
            updateConnectionStatus(true);
            reconnectAttempts = 0; // Reset on successful connection
            
            // Subscribe to all trading pairs
            websocket.send(JSON.stringify({
                action: 'subscribe',
                symbols: ['BTC-USD', 'ETH-USD', 'SOL-USD']
            }));
        };
        
        websocket.onmessage = (event) => {
            const data = JSON.parse(event.data);
            handleWebSocketMessage(data);
        };
        
        websocket.onclose = () => {
            console.log('WebSocket disconnected');
            updateConnectionStatus(false);
            
            // Attempt reconnection with exponential backoff
            if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
                const delay = getReconnectDelay();
                console.log(`Reconnecting in ${Math.round(delay / 1000)}s (attempt ${reconnectAttempts + 1}/${MAX_RECONNECT_ATTEMPTS})`);
                reconnectAttempts++;
                setTimeout(initializeWebSocket, delay);
            } else {
                console.log('Max reconnection attempts reached. Please refresh the page.');
                showNotification('Connection lost. Please refresh the page.', 'error');
            }
        };
        
        websocket.onerror = (error) => {
            console.error('WebSocket error:', error);
            updateConnectionStatus(false);
        };
    } catch (error) {
        console.error('Failed to initialize WebSocket:', error);
        updateConnectionStatus(false);
    }
}

function updateConnectionStatus(connected) {
    const statusEl = document.getElementById('connection-status');
    if (connected) {
        statusEl.textContent = 'Connected';
        statusEl.className = 'connected';
    } else {
        statusEl.textContent = 'Disconnected';
        statusEl.className = 'disconnected';
    }
}

function handleWebSocketMessage(data) {
    if (data.type === 'trade') {
        addTradeToTable(data.data);
        showNotification(`Trade executed: ${data.data.symbol} @ ${data.data.price}`, 'success');
    }
}

// Order Submission
async function submitOrder(event) {
    event.preventDefault();
    
    const order = {
        symbol: document.getElementById('symbol').value,
        side: document.getElementById('side').value,
        order_type: document.getElementById('order-type').value,
        quantity: parseFloat(document.getElementById('quantity').value)
    };
    
    if (order.order_type === 'limit') {
        order.price = parseFloat(document.getElementById('price').value);
    }
    
    try {
        const response = await fetch(`${CONFIG.HTTP_API_ENDPOINT}/orders`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                ...(authToken && { 'Authorization': `Bearer ${authToken}` })
            },
            body: JSON.stringify(order)
        });
        
        const result = await response.json();
        
        if (response.ok) {
            showNotification(`Order submitted: ${result.order_id}`, 'success');
            document.getElementById('order-form').reset();
        } else {
            showNotification(`Error: ${result.error}`, 'error');
        }
    } catch (error) {
        console.error('Order submission failed:', error);
        showNotification('Failed to submit order. Please try again.', 'error');
    }
}

// Toggle price field visibility for market orders
function togglePriceField() {
    const orderType = document.getElementById('order-type').value;
    const priceGroup = document.getElementById('price-group');
    const priceInput = document.getElementById('price');
    
    if (orderType === 'market') {
        priceGroup.style.display = 'none';
        priceInput.removeAttribute('required');
    } else {
        priceGroup.style.display = 'flex';
        priceInput.setAttribute('required', 'required');
    }
}

// Add trade to the trades table
function addTradeToTable(trade) {
    const tbody = document.getElementById('trades-body');
    const row = document.createElement('tr');
    
    const time = new Date(trade.timestamp).toLocaleTimeString();
    
    row.innerHTML = `
        <td>${time}</td>
        <td>${trade.symbol}</td>
        <td>$${formatNumber(trade.price)}</td>
        <td>${formatNumber(trade.quantity)}</td>
        <td>$${formatNumber(trade.total_value)}</td>
    `;
    
    // Insert at the top
    tbody.insertBefore(row, tbody.firstChild);
    
    // Keep only the last 50 trades
    while (tbody.children.length > 50) {
        tbody.removeChild(tbody.lastChild);
    }
}

// Load mock order book data
function loadMockOrderBook() {
    const asks = [
        { price: 50150, quantity: 1.5 },
        { price: 50200, quantity: 0.8 },
        { price: 50250, quantity: 2.3 },
        { price: 50300, quantity: 1.1 },
        { price: 50350, quantity: 0.5 }
    ];
    
    const bids = [
        { price: 50050, quantity: 2.0 },
        { price: 50000, quantity: 1.2 },
        { price: 49950, quantity: 3.5 },
        { price: 49900, quantity: 0.9 },
        { price: 49850, quantity: 1.8 }
    ];
    
    const asksContainer = document.getElementById('asks-list');
    const bidsContainer = document.getElementById('bids-list');
    
    asks.forEach(order => {
        const row = document.createElement('div');
        row.className = 'book-row';
        row.innerHTML = `<span>$${formatNumber(order.price)}</span><span>${order.quantity}</span>`;
        asksContainer.appendChild(row);
    });
    
    bids.forEach(order => {
        const row = document.createElement('div');
        row.className = 'book-row';
        row.innerHTML = `<span>$${formatNumber(order.price)}</span><span>${order.quantity}</span>`;
        bidsContainer.appendChild(row);
    });
}

// Authentication functions
function login() {
    // Redirect to Cognito Hosted UI
    const loginUrl = `https://${CONFIG.COGNITO_DOMAIN}/login?` +
        `client_id=${CONFIG.COGNITO_CLIENT_ID}&` +
        `response_type=token&` +
        `scope=email+openid+profile&` +
        `redirect_uri=${encodeURIComponent(window.location.origin + '/callback')}`;
    
    window.location.href = loginUrl;
}

function logout() {
    authToken = null;
    localStorage.removeItem('auth_token');
    updateAuthUI(false);
}

function updateAuthUI(isLoggedIn, email = '') {
    const userStatus = document.getElementById('user-status');
    const loginBtn = document.getElementById('login-btn');
    const logoutBtn = document.getElementById('logout-btn');
    
    if (isLoggedIn) {
        userStatus.textContent = email;
        loginBtn.style.display = 'none';
        logoutBtn.style.display = 'block';
    } else {
        userStatus.textContent = 'Not logged in';
        loginBtn.style.display = 'block';
        logoutBtn.style.display = 'none';
    }
}

// Check for auth token in URL hash (after Cognito redirect)
function checkAuthCallback() {
    const hash = window.location.hash.substring(1);
    if (hash) {
        const params = new URLSearchParams(hash);
        const token = params.get('access_token');
        if (token) {
            authToken = token;
            localStorage.setItem('auth_token', token);
            window.location.hash = '';
            updateAuthUI(true, 'User');
        }
    }
}

// Utility functions
function formatNumber(num) {
    return parseFloat(num).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });
}

function showNotification(message, type) {
    const notification = document.createElement('div');
    notification.className = `notification ${type}`;
    notification.textContent = message;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.remove();
    }, 3000);
}

// Check for existing auth token
const savedToken = localStorage.getItem('auth_token');
if (savedToken) {
    authToken = savedToken;
    updateAuthUI(true, 'User');
}

// Check for Cognito callback
checkAuthCallback();
