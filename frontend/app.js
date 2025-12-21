// ============================================================================
// Configuration - REPLACE THESE WITH YOUR ACTUAL URLs
// ============================================================================

// Конфигурация API (Ваши реальные адреса с AWS)
const API_URL = "https://i5olri2bdh.execute-api.eu-west-1.amazonaws.com/dev/orders";
const WS_URL = "wss://jcniktjxz4.execute-api.eu-west-1.amazonaws.com/dev";

// ============================================================================
// Global State
// ============================================================================

let ws = null;
let reconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = 5;

// ============================================================================
// WebSocket Management
// ============================================================================

function connectWebSocket() {
    console.log('Connecting to WebSocket:', WS_URL);
    
    ws = new WebSocket(WS_URL);
    
    ws.onopen = function(event) {
        console.log('WebSocket connected');
        reconnectAttempts = 0;
        updateWSStatus('Connected', 'success');
    };
    
    ws.onclose = function(event) {
        console.log('WebSocket disconnected');
        updateWSStatus('Disconnected', 'danger');
        
        // Attempt reconnection
        if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
            reconnectAttempts++;
            console.log(`Reconnection attempt ${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS}`);
            setTimeout(connectWebSocket, 3000);
        }
    };
    
    ws.onerror = function(error) {
        console.error('WebSocket error:', error);
        updateWSStatus('Error', 'warning');
    };
    
    ws.onmessage = function(event) {
        try {
            const message = JSON.parse(event.data);
            console.log('WebSocket message:', message);
            
            if (message.type === 'trade') {
                addTradeToTable(message.data);
            }
        } catch (error) {
            console.error('Error parsing WebSocket message:', error);
        }
    };
}

function updateWSStatus(status, type) {
    const statusBadge = document.getElementById('wsStatus');
    statusBadge.textContent = status;
    statusBadge.className = `badge bg-${type}`;
}

// ============================================================================
// Trade Display
// ============================================================================

function addTradeToTable(trade) {
    const tbody = document.getElementById('tradesTableBody');
    
    // Remove "waiting for trades" message if present
    if (tbody.children.length === 1 && tbody.children[0].children.length === 1) {
        tbody.innerHTML = '';
    }
    
    // Format timestamp
    const timestamp = new Date(trade.timestamp);
    const timeStr = timestamp.toLocaleTimeString();
    
    // Format price and amount
    const price = parseFloat(trade.price).toFixed(2);
    const amount = parseFloat(trade.amount).toFixed(4);
    
    // Determine side from order IDs (simplified)
    const side = determineSide(trade);
    const sideClass = side === 'BUY' ? 'trade-buy' : 'trade-sell';
    
    // Create new row
    const row = document.createElement('tr');
    row.innerHTML = `
        <td>${timeStr}</td>
        <td>${trade.pair}</td>
        <td class="${sideClass}">${side}</td>
        <td>$${price}</td>
        <td>${amount}</td>
    `;
    
    // Insert at the top
    tbody.insertBefore(row, tbody.firstChild);
    
    // Keep only last 50 trades
    while (tbody.children.length > 50) {
        tbody.removeChild(tbody.lastChild);
    }
}

function determineSide(trade) {
    // Simple heuristic: if we have more info, use it
    // For now, alternate or use random
    return Math.random() > 0.5 ? 'BUY' : 'SELL';
}

// ============================================================================
// Order Submission
// ============================================================================

async function submitOrder(side) {
    // Get form values
    const pair = document.getElementById('pairSelect').value;
    const price = parseFloat(document.getElementById('priceInput').value);
    const amount = parseFloat(document.getElementById('amountInput').value);
    const userId = document.getElementById('userIdInput').value;
    
    // Validate
    if (!price || price <= 0) {
        showOrderStatus('Please enter a valid price', 'danger');
        return;
    }
    
    if (!amount || amount <= 0) {
        showOrderStatus('Please enter a valid amount', 'danger');
        return;
    }
    
    if (!userId.trim()) {
        showOrderStatus('Please enter a user ID', 'danger');
        return;
    }
    
    // Prepare order data
    const orderData = {
        pair: pair,
        side: side.toUpperCase(),
        price: price,
        amount: amount,
        user_id: userId
    };
    
    console.log('Submitting order:', orderData);
    showOrderStatus('Submitting order...', 'info');
    
    try {
        const response = await fetch(API_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(orderData)
        });
        
        const result = await response.json();
        
        if (response.ok) {
            console.log('Order submitted successfully:', result);
            showOrderStatus(`✓ Order ${result.orderId} submitted successfully!`, 'success');
            
            // Clear form
            document.getElementById('priceInput').value = '';
            document.getElementById('amountInput').value = '';
        } else {
            console.error('Order submission failed:', result);
            showOrderStatus(`✗ Error: ${result.error || 'Failed to submit order'}`, 'danger');
        }
    } catch (error) {
        console.error('Network error:', error);
        showOrderStatus(`✗ Network error: ${error.message}`, 'danger');
    }
}

function showOrderStatus(message, type) {
    const statusDiv = document.getElementById('orderStatus');
    statusDiv.textContent = message;
    statusDiv.className = `alert alert-${type}`;
    statusDiv.classList.remove('d-none');
    
    // Auto-hide after 5 seconds for success messages
    if (type === 'success') {
        setTimeout(() => {
            statusDiv.classList.add('d-none');
        }, 5000);
    }
}

// ============================================================================
// Event Listeners
// ============================================================================

document.addEventListener('DOMContentLoaded', function() {
    console.log('Application initialized');
    
    // Check if URLs are configured
    if (API_URL.includes('YOUR_') || WS_URL.includes('YOUR_')) {
        console.warn('⚠️ Please update API_URL and WS_URL in app.js with your actual endpoints');
        showOrderStatus('⚠️ API URLs not configured. Please update app.js', 'warning');
    }
    
    // Connect WebSocket
    if (!WS_URL.includes('YOUR_')) {
        connectWebSocket();
    } else {
        updateWSStatus('Not Configured', 'secondary');
    }
    
    // Buy button
    document.getElementById('buyBtn').addEventListener('click', function() {
        submitOrder('BUY');
    });
    
    // Sell button
    document.getElementById('sellBtn').addEventListener('click', function() {
        submitOrder('SELL');
    });
    
    // Form submission (Enter key)
    document.getElementById('orderForm').addEventListener('submit', function(e) {
        e.preventDefault();
    });
});

// ============================================================================
// Cleanup on page unload
// ============================================================================

window.addEventListener('beforeunload', function() {
    if (ws) {
        ws.close();
    }
});
