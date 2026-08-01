<?php
error_reporting(0);
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
require_once('database.php');

// READ-ONLY API — only SELECT queries. Nothing is inserted, updated, or deleted here.
$method = $_SERVER['REQUEST_METHOD'];
if ($method !== 'GET') {
    echo json_encode(["success" => false, "message" => "Method not allowed"]);
    exit;
}

$startDate   = isset($_GET['start_date'])   ? $_GET['start_date']   : date('Y-m-01');
$endDate     = isset($_GET['end_date'])     ? $_GET['end_date']     : date('Y-m-d');
$reportType  = isset($_GET['report_type']) ? $_GET['report_type']  : '';

if (empty($reportType)) {
    echo json_encode(["success" => false, "message" => "report_type is required"]);
    exit;
}

// Sanitise dates
$startDate = mysqli_real_escape_string($dbConn, $startDate);
$endDate   = mysqli_real_escape_string($dbConn, $endDate);

$query = "";

switch ($reportType) {

    // -----------------------------------------------------------------------
    case "Customer Orders":
        $query = "SELECT
            cid            AS id,
            tracking       AS tracking_no,
            reference_no,
            rev_name       AS customer_name,
            cc             AS customer_code,
            ship_name      AS sender_name,
            s_add          AS origin,
            rev_name       AS receiver_name,
            r_add          AS destination,
            last_updated   AS delivery_date,
            book_date      AS booking_date,
            status         AS delivery_status,
            payment        AS payment_status,
            phone          AS sender_phone,
            r_phone        AS receiver_phone,
            correo         AS sender_email,
            email          AS customer_email,
            shipping_subtotal AS subtotal,
            type           AS shipment_type,
            shipping_method,
            book_mode      AS booking_mode,
            mode           AS service_mode,
            comments       AS remarks,
            pesoreal       AS weight,
            qty            AS quantity,
            altura         AS height,
            ancho          AS width,
            longitud       AS length,
            totalpeso      AS volumetric_weight,
            invice_no      AS origin_office,
            state          AS pickup_state,
            ciudad         AS pickup_city,
            zipcode        AS pickup_zipcode,
            state1         AS destination_state,
            city1          AS destination_city,
            zipcode1       AS destination_zipcode,
            'courier'      AS source_table
        FROM courier
        WHERE book_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY book_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "Fulfillment":
        $query = "SELECT
            F.id           AS id,
            F.tracking_no,
            NULL           AS reference_no,
            F.customer_name,
            F.customer_code,
            F.company_name AS sender_name,
            F.origin,
            F.customer_name AS receiver_name,
            F.destination,
            F.delivery_date,
            F.order_date   AS booking_date,
            F.order_status AS delivery_status,
            F.payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            F.total_value  AS subtotal,
            F.shipping_method AS shipment_type,
            F.shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            F.reason       AS remarks,
            NULL           AS weight,
            F.ordered_qty  AS quantity,
            'fulfillment'  AS source_table
        FROM fulfillment F
        WHERE F.created_at BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY F.id DESC";
        break;

    // -----------------------------------------------------------------------
    case "Inscan":
        $query = "SELECT
            id,
            tracking_no,
            NULL           AS reference_no,
            customer_name  AS customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            NULL           AS origin,
            NULL           AS receiver_name,
            NULL           AS destination,
            inscan_datetime AS delivery_date,
            inscan_datetime AS booking_date,
            inscan_status  AS delivery_status,
            NULL           AS payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            0              AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            NULL           AS remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'inscan'       AS source_table
        FROM inscan
        WHERE inscan_datetime BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY inscan_datetime DESC";
        break;

    // -----------------------------------------------------------------------
    case "Outscan":
        $query = "SELECT
            id,
            tracking_no,
            NULL           AS reference_no,
            customer_name  AS customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            NULL           AS origin,
            NULL           AS receiver_name,
            NULL           AS destination,
            outscan_datetime AS delivery_date,
            outscan_datetime AS booking_date,
            outscan_status AS delivery_status,
            NULL           AS payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            0              AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            NULL           AS remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'outscan'      AS source_table
        FROM outscan
        WHERE outscan_datetime BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY outscan_datetime DESC";
        break;

    // -----------------------------------------------------------------------
    case "Delivered":
        // Union of delivered table + courier table (status=Delivered)
        $query = "
        SELECT
            id             AS id,
            tracking_no,
            reference_no,
            customer_name,
            customer_code,
            customer_name  AS sender_name,
            origin,
            customer_name  AS receiver_name,
            destination,
            delivery_date,
            booking_datetime AS booking_date,
            delivery_status,
            payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            total_order_value AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            remarks,
            NULL           AS weight,
            NULL           AS quantity,
            NULL           AS pickup_state,
            NULL           AS pickup_city,
            NULL           AS pickup_zipcode,
            NULL           AS destination_state,
            NULL           AS destination_city,
            NULL           AS destination_zipcode,
            'delivered'    AS source_table
        FROM delivered
        WHERE delivery_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'

        UNION ALL

        SELECT
            cid            AS id,
            tracking       AS tracking_no,
            reference_no,
            rev_name       AS customer_name,
            cc             AS customer_code,
            ship_name      AS sender_name,
            s_add          AS origin,
            rev_name       AS receiver_name,
            r_add          AS destination,
            last_updated   AS delivery_date,
            book_date      AS booking_date,
            status         AS delivery_status,
            payment        AS payment_status,
            phone          AS sender_phone,
            r_phone        AS receiver_phone,
            shipping_subtotal AS subtotal,
            type           AS shipment_type,
            shipping_method,
            book_mode      AS booking_mode,
            mode           AS service_mode,
            comments       AS remarks,
            pesoreal       AS weight,
            qty            AS quantity,
            altura         AS height,
            ancho          AS width,
            longitud       AS length,
            totalpeso      AS volumetric_weight,
            invice_no      AS origin_office,
            state          AS pickup_state,
            ciudad         AS pickup_city,
            zipcode        AS pickup_zipcode,
            state1         AS destination_state,
            city1          AS destination_city,
            zipcode1       AS destination_zipcode,
            'courier'      AS source_table
        FROM courier
        WHERE status = 'Delivered'
        AND last_updated BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY delivery_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "RTS":
        $query = "SELECT
            id,
            tracking_no,
            reference_no,
            customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            origin,
            NULL           AS receiver_name,
            destination,
            return_request_date AS delivery_date,
            return_request_date AS booking_date,
            return_status  AS delivery_status,
            payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            total_order_value AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'rts'          AS source_table
        FROM rts
        WHERE return_request_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY return_request_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "RTO":
        $query = "SELECT
            id,
            tracking_no,
            reference_no,
            customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            origin,
            NULL           AS receiver_name,
            destination,
            rto_initiation_date AS delivery_date,
            rto_initiation_date AS booking_date,
            rto_status     AS delivery_status,
            payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            total_order_value AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'rto'          AS source_table
        FROM rto
        WHERE rto_initiation_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY rto_initiation_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "Cancelled Shipments":
        $query = "SELECT
            id,
            tracking_no,
            reference_no,
            customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            origin,
            NULL           AS receiver_name,
            destination,
            shipment_cancel_date AS delivery_date,
            shipment_cancel_date AS booking_date,
            cancel_status  AS delivery_status,
            payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            total_order_value AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'canceled_shipments' AS source_table
        FROM canceled_shipments
        WHERE shipment_cancel_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY shipment_cancel_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "Process for RTO":
        $query = "SELECT
            id,
            tracking_no,
            reference_no,
            customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            origin,
            NULL           AS receiver_name,
            destination,
            rto_initiation_date AS delivery_date,
            rto_initiation_date AS booking_date,
            rto_status     AS delivery_status,
            payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            total_order_value AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'process_for_rto' AS source_table
        FROM process_for_rto
        WHERE rto_initiation_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY rto_initiation_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "RTO Inscan":
        $query = "SELECT
            id,
            tracking_no,
            NULL           AS reference_no,
            customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            NULL           AS origin,
            NULL           AS receiver_name,
            NULL           AS destination,
            rto_initiation_date AS delivery_date,
            rto_initiation_date AS booking_date,
            rto_status     AS delivery_status,
            NULL           AS payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            0              AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            NULL           AS remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'rto_inscan'   AS source_table
        FROM rto_inscan
        WHERE rto_initiation_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY rto_initiation_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "RTO Outscan":
        $query = "SELECT
            id,
            tracking_no,
            NULL           AS reference_no,
            customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            NULL           AS origin,
            NULL           AS receiver_name,
            NULL           AS destination,
            rto_initiation_date AS delivery_date,
            rto_initiation_date AS booking_date,
            rto_status     AS delivery_status,
            NULL           AS payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            0              AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            NULL           AS remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'rto_outscan'  AS source_table
        FROM rto_outscan
        WHERE rto_initiation_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY rto_initiation_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "RTO Delivered":
        $query = "SELECT
            id,
            tracking_no,
            reference_no,
            customer_name,
            NULL           AS customer_code,
            NULL           AS sender_name,
            origin,
            NULL           AS receiver_name,
            destination,
            rto_initiation_date AS delivery_date,
            rto_initiation_date AS booking_date,
            rto_status     AS delivery_status,
            payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            total_order_value AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            remarks,
            NULL           AS weight,
            NULL           AS quantity,
            'rto_delivered' AS source_table
        FROM rto_delivered
        WHERE rto_initiation_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY rto_initiation_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "Undelivered Shipments":
        $query = "SELECT
            cid            AS id,
            tracking       AS tracking_no,
            reference_no,
            rev_name       AS customer_name,
            cc             AS customer_code,
            ship_name      AS sender_name,
            s_add          AS origin,
            rev_name       AS receiver_name,
            r_add          AS destination,
            last_updated   AS delivery_date,
            book_date      AS booking_date,
            status         AS delivery_status,
            payment        AS payment_status,
            phone          AS sender_phone,
            r_phone        AS receiver_phone,
            shipping_subtotal AS subtotal,
            type           AS shipment_type,
            shipping_method,
            book_mode      AS booking_mode,
            mode           AS service_mode,
            comments       AS remarks,
            pesoreal       AS weight,
            qty            AS quantity,
            altura         AS height,
            ancho          AS width,
            longitud       AS length,
            totalpeso      AS volumetric_weight,
            invice_no      AS origin_office,
            'courier'      AS source_table
        FROM courier
        WHERE status != 'Delivered'
        AND book_date BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY book_date DESC";
        break;

    // -----------------------------------------------------------------------
    case "Inventory":
        $query = "SELECT
            s.storage_id   AS id,
            s.item_code    AS tracking_no,
            NULL           AS reference_no,
            s.customer_name,
            s.customer_code,
            s.company_name AS sender_name,
            NULL           AS origin,
            s.customer_name AS receiver_name,
            NULL           AS destination,
            s.created_at   AS delivery_date,
            s.created_at   AS booking_date,
            NULL           AS delivery_status,
            NULL           AS payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            s.total_value  AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            s.remarks,
            NULL           AS weight,
            s.current_qty  AS quantity,
            'storage'      AS source_table
        FROM storage s
        WHERE s.created_at BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY s.created_at DESC";
        break;

    // -----------------------------------------------------------------------
    case "Storage":
        $query = "SELECT
            s.storage_id   AS id,
            s.item_code    AS tracking_no,
            NULL           AS reference_no,
            s.customer_name,
            s.customer_code,
            s.company_name AS sender_name,
            NULL           AS origin,
            s.customer_name AS receiver_name,
            NULL           AS destination,
            s.created_at   AS delivery_date,
            s.created_at   AS booking_date,
            NULL           AS delivery_status,
            NULL           AS payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            s.total_value  AS subtotal,
            NULL           AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            s.remarks,
            NULL           AS weight,
            s.current_qty  AS quantity,
            'storage'      AS source_table
        FROM storage s
        WHERE s.created_at BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY s.created_at DESC";
        break;

    // -----------------------------------------------------------------------
    case "Products":
        $query = "SELECT
            p.id,
            p.item_code    AS tracking_no,
            NULL           AS reference_no,
            p.customer_name,
            p.client_id    AS customer_code,
            p.company_name AS sender_name,
            NULL           AS origin,
            p.customer_name AS receiver_name,
            NULL           AS destination,
            p.created_at   AS delivery_date,
            p.created_at   AS booking_date,
            p.availability_status AS delivery_status,
            NULL           AS payment_status,
            NULL           AS sender_phone,
            NULL           AS receiver_phone,
            p.base_price   AS subtotal,
            p.category     AS shipment_type,
            NULL           AS shipping_method,
            NULL           AS booking_mode,
            NULL           AS service_mode,
            p.description  AS remarks,
            NULL           AS weight,
            p.stock_quantity AS quantity,
            'products'     AS source_table
        FROM products p
        WHERE p.created_at BETWEEN '$startDate 00:00:00' AND '$endDate 23:59:59'
        ORDER BY p.id DESC";
        break;

    // -----------------------------------------------------------------------
    default:
        echo json_encode(["success" => false, "message" => "Unknown report_type: $reportType"]);
        exit;
}

// Execute and return results
$shipments = [];
$result = mysqli_query($dbConn, $query);

if ($result) {
    while ($row = mysqli_fetch_assoc($result)) {
        $shipments[] = $row;
    }
    echo json_encode([
        "success"     => true,
        "report_type" => $reportType,
        "count"       => count($shipments),
        "shipments"   => $shipments
    ]);
} else {
    echo json_encode([
        "success" => false,
        "message" => "DB error: " . mysqli_error($dbConn)
    ]);
}
?>
