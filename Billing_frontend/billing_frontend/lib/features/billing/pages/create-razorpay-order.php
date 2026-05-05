<?php
/***
 * CREATE RAZORPAY ORDER
 * This creates an order and returns order_id for instant payment confirmation
 */

// Set CORS headers first - BEFORE any other output
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Accept');
header('Access-Control-Max-Age: 86400');
header('Content-Type: application/json');

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Razorpay API credentials
const RAZORPAY_KEY_ID = 'rzp_live_SEQ3G3rfsSW9QB';
const RAZORPAY_KEY_SECRET = 'ucjm2iEG58I2q6NTbxpXQRtj';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

// Get amount from request
$input = json_decode(file_get_contents('php://input'), true);
$amount = isset($input['amount']) ? intval($input['amount']) : 0;
$currency = $input['currency'] ?? 'INR';
$receipt = 'order_' . time();

if ($amount <= 0) {
    echo json_encode(['error' => 'Invalid amount']);
    exit;
}

// Create Razorpay order
$orderData = [
    'amount' => $amount * 100, // Amount in paise
    'currency' => $currency,
    'receipt' => $receipt,
    'payment_capture' => 1 // Auto capture
];

$ch = curl_init('https://api.razorpay.com/v1/orders');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($orderData));
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'Authorization: Basic ' . base64_encode(RAZORPAY_KEY_ID . ':' . RAZORPAY_KEY_SECRET)
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($httpCode === 200) {
    echo $response;
} else {
    http_response_code($httpCode);
    echo json_encode(['error' => 'Failed to create order', 'details' => $response]);
}