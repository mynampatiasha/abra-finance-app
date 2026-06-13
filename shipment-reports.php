<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('database.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

date_default_timezone_set($_SESSION['ge_timezone']);	
$fechai=date('Y-m-d');
$fechaf=date('Y-m-d');

$styling=mysqli_fetch_array(mysqli_query($dbConn, "SELECT * FROM styles"));
isUser();												 

// Load warehouses from the warehouse system
define('WAREHOUSE_DATA_DIR', __DIR__ . '/warehouse_data/');
define('WAREHOUSES_FILE', WAREHOUSE_DATA_DIR . 'warehouses.json');
define('USERS_FILE', WAREHOUSE_DATA_DIR . 'users.json');

function load_warehouses_data() {
    if (file_exists(WAREHOUSES_FILE)) {
        $data = file_get_contents(WAREHOUSES_FILE);
        return json_decode($data, true) ?: [];
    }
    return [];
}

function load_users_data() {
    if (file_exists(USERS_FILE)) {
        $data = file_get_contents(USERS_FILE);
        return json_decode($data, true) ?: [];
    }
    return [];
}

$warehouses_list = load_warehouses_data();
$users_data = load_users_data();

// Create warehouse ID to name mapping
$warehouse_id_lookup = [];
foreach ($warehouses_list as $warehouse) {
    $warehouse_id_lookup[$warehouse['id']] = $warehouse['name'];
}

// Get the report type and date range from the form
$report_type = isset($_GET['report_type']) ? $_GET['report_type'] : '';
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : '';
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : '';
$export = isset($_GET['export']) ? $_GET['export'] : '0';

// Initialize the query variable
$query = "";
$column_mapping = []; // Initialize for later use

// SQL query based on the report type
switch ($report_type) {
    case "Customer Orders":
        $table = "courier";
        $query = "SELECT 
			cid AS 'ID',
			tracking AS 'Tracking Number',
            reference_no AS 'Reference Number',
			s_add AS 'Origin',
			r_add AS 'Destination',
			rev_name AS 'Customer Name',
			status AS 'Booking Status',
			status AS 'Delivery Status',
            book_date AS 'Booking Date',
			last_updated AS 'Delivery Date',
			r_add AS 'Destination Address',
			comments AS 'Remarks',
			last_updated AS 'Last Updated',
			enquiry_number AS 'Enquiry Number',
			cons_no AS 'Con No',
			letra AS 'Letter Used',
			ship_name AS 'Sender Name',
			phone AS 'Sender Phone',
			s_add AS 'Sender Address',
			cc AS 'Identification Number',
			correo AS 'Sender Email Address',
			rev_name AS 'Receiver Name',
			r_phone AS 'Receiver Phone',
			telefono1 AS 'Receiver Phone 2',
			cc_r AS 'Receiver Identification',
			email AS 'Receiver Email',
			type AS 'Type',
			shipping_subtotal AS 'Subtotal Shipping',
			currency AS 'Currency',
			altura AS 'Height',
			ancho AS 'Width',
			longitud AS 'Length',
			totalpeso AS 'Total Volumetric Weight',
			invice_no AS 'Origin Office',
			qty AS 'Quantity',
			book_mode AS 'Booking Mode',
			shipping_method AS 'Shipping Method',
			mode AS 'Service Mode',
			pick_date AS 'Pickup Date',
			schedule AS 'Delivery Date (Scheduled)',
			pick_time AS 'Pickup Country',
			state AS 'Pickup State',
			ciudad AS 'Pickup City',
			zipcode AS 'Pickup Zip Code',
			paisdestino AS 'Destination Country',
			state1 AS 'Destination State',
			city1 AS 'Destination City',
			zipcode1 AS 'Destination Zip Code',
			dom_internation AS 'Domestic/International',
			comments AS 'Comments',
			enquiry_date AS 'Enquiry Date',
			payment AS 'Payment',
			paymode AS 'Pay Mode',
			officename AS 'Entry Staff Role',
			user AS 'Entry User',
			pesoreal AS 'Weight'
		FROM courier 
		WHERE book_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
		
    case "Fulfillment":
        // This logic is from the new file, as requested
        $table = "fulfillment";
        $query = "SELECT 
            F.id AS 'ID',
            F.warehouse_id AS 'Warehouse ID',
            F.tracking_no AS 'Tracking Number',
            F.company_name AS 'Company Name',
            F.customer_code AS 'Customer Code',
            F.customer_name AS 'Customer Name',
            F.order_id AS 'Order ID',
            F.product_id AS 'Product ID',
            F.storage_id AS 'Storage ID',
            F.product_name AS 'Product Name',
            F.order_date AS 'Order Date',
            F.origin AS 'Origin',
            F.destination AS 'Destination',
            F.aging_date AS 'Aging Date',
            F.delivery_date AS 'Delivery Date',
            F.actual_fulfillment_date AS 'Actual Fulfillment Date',
            F.ordered_qty AS 'Ordered Quantity',
            F.fulfilled_qty AS 'Fulfilled Quantity',
            F.backorder_qty AS 'Backorder Quantity',
            F.current_stock AS 'Stock at Fulfillment',
            F.shipping_method AS 'Shipping Method',
            F.order_status AS 'Order Status',
            F.reason AS 'Reason',
            F.unit_price AS 'Unit Price',
            F.total_value AS 'Total Value',
            F.payment_status AS 'Payment Status',
            F.created_at AS 'Created At'
        FROM fulfillment F 
        WHERE F.created_at BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'
        ORDER BY F.id DESC";
        break;
        
    case "Inscan":
        $table = "inscan";
        $query = "SELECT * FROM inscan WHERE inscan_datetime BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
    case "Outscan":
        $table = "outscan";
        $query = "SELECT * FROM outscan WHERE outscan_datetime BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
    case "Delivered":
        // This comprehensive query is from the old file
		$table = "delivered";
		$query = "SELECT 
			id AS 'ID',
			tracking_no AS 'Tracking Number',
			reference_no AS 'Reference Number',
			delivery_aggregator AS 'Delivery Agent',
			order_id AS 'Order ID',
			product_id AS 'Product ID',
			product_name AS 'Product Name',
			dispatched_from AS 'Dispatched From',
			origin AS 'Origin',
			destination AS 'Destination',
			company_name AS 'Company Name',
			customer_code AS 'Customer Code',
			customer_name AS 'Customer Name',
			booking_datetime AS 'Booking DateTime',
			booking_status AS 'Booking Status',
			inscan_datetime AS 'Inscan DateTime',
			inscan_status AS 'Inscan Status',
			outscan_datetime AS 'Outscan DateTime',
			outscan_status AS 'Outscan Status',
			delivery_status AS 'Delivery Status',
			delivery_date AS 'Delivery Date',
			delivered_by AS 'Delivered By',
			destination_address AS 'Destination Address',
			payment_status AS 'Payment Status',
			invoice_no AS 'Invoice No',
			total_order_value AS 'Total Order Value',
			remarks AS 'Remarks',
			date_time AS 'Last Updated',
			NULL AS 'Enquiry Number',
			NULL AS 'Con No',
			NULL AS 'Letter Used',
			NULL AS 'Sender Name',
			NULL AS 'Sender Phone',
			NULL AS 'Sender Address',
			NULL AS 'Identification Number',
			NULL AS 'Sender Email Address',
			NULL AS 'Receiver Name',
			NULL AS 'Receiver Phone',
			NULL AS 'Receiver Phone 2',
			NULL AS 'Receiver Identification',
			NULL AS 'Receiver Email',
			NULL AS 'Type',
			NULL AS 'Subtotal Shipping',
			NULL AS 'Currency',
			NULL AS 'Height',
			NULL AS 'Width',
			NULL AS 'Length',
			NULL AS 'Total Volumetric Weight',
			NULL AS 'Origin Office',
			NULL AS 'Quantity',
			NULL AS 'Booking Mode',
			NULL AS 'Shipping Method',
			NULL AS 'Service Mode',
			NULL AS 'Pickup Date',
			NULL AS 'Delivery Date (Scheduled)',
			NULL AS 'Pickup Country',
			NULL AS 'Pickup State',
			NULL AS 'Pickup City',
			NULL AS 'Pickup Zip Code',
			NULL AS 'Destination Country',
			NULL AS 'Destination State',
			NULL AS 'Destination City',
			NULL AS 'Destination Zip Code',
			NULL AS 'Domestic/International',
			NULL AS 'Comments',
			NULL AS 'Enquiry Date',
			NULL AS 'Payment',
			NULL AS 'Pay Mode',
			NULL AS 'Entry Staff Role',
			NULL AS 'Entry User',
			NULL AS 'Weight'
		FROM delivered 
		WHERE delivery_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59' 

		UNION 

		SELECT 
			cid AS 'ID',
			tracking AS 'Tracking Number',
			reference_no AS 'Reference Number',
			delivery_aggregator AS 'Delivery Agent',
			NULL AS 'Order ID',
			NULL AS 'Product ID',
			NULL AS 'Product Name',
			NULL AS 'Dispatched From',
			s_add AS 'Origin',
			r_add AS 'Destination',
			NULL AS 'Company Name',
			NULL AS 'Customer Code',
			rev_name AS 'Customer Name',
			NULL AS 'Booking DateTime',
			status AS 'Booking Status',
			NULL AS 'Inscan DateTime',
			NULL AS 'Inscan Status',
			NULL AS 'Outscan DateTime',
			NULL AS 'Outscan Status',
			status AS 'Delivery Status',
			last_updated AS 'Delivery Date',
			NULL AS 'Delivered By',
			r_add AS 'Destination Address',
			NULL AS 'Payment Status',
			NULL AS 'Invoice No',
			NULL AS 'Total Order Value',
			comments AS 'Remarks',
			last_updated AS 'Last Updated',
			enquiry_number AS 'Enquiry Number',
			cons_no AS 'Con No',
			letra AS 'Letter Used',
			ship_name AS 'Sender Name',
			phone AS 'Sender Phone',
			s_add AS 'Sender Address',
			cc AS 'Identification Number',
			correo AS 'Sender Email Address',
			rev_name AS 'Receiver Name',
			r_phone AS 'Receiver Phone',
			telefono1 AS 'Receiver Phone 2',
			cc_r AS 'Receiver Identification',
			email AS 'Receiver Email',
			type AS 'Type',
			shipping_subtotal AS 'Subtotal Shipping',
			currency AS 'Currency',
			altura AS 'Height',
			ancho AS 'Width',
			longitud AS 'Length',
			totalpeso AS 'Total Volumetric Weight',
			invice_no AS 'Origin Office',
			qty AS 'Quantity',
			book_mode AS 'Booking Mode',
			shipping_method AS 'Shipping Method',
			mode AS 'Service Mode',
			pick_date AS 'Pickup Date',
			schedule AS 'Delivery Date (Scheduled)',
			pick_time AS 'Pickup Country',
			state AS 'Pickup State',
			ciudad AS 'Pickup City',
			zipcode AS 'Pickup Zip Code',
			paisdestino AS 'Destination Country',
			state1 AS 'Destination State',
			city1 AS 'Destination City',
			zipcode1 AS 'Destination Zip Code',
			dom_internation AS 'Domestic/International',
			comments AS 'Comments',
			enquiry_date AS 'Enquiry Date',
			payment AS 'Payment',
			paymode AS 'Pay Mode',
			officename AS 'Entry Staff Role',
			user AS 'Entry User',
			pesoreal AS 'Weight'
		FROM courier 
		WHERE status = 'Delivered' 
		AND last_updated BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
		break;
		
	case "RTS":
        $table = "rts";
        $query = "SELECT * FROM rts WHERE return_request_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
	case "RTO":
        $table = "rto";
        $query = "SELECT * FROM rto WHERE rto_initiation_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
	case "Cancelled Shipments":
        $table = "canceled_shipments";
        $query = "SELECT * FROM canceled_shipments WHERE shipment_cancel_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
	case "Process for RTO":
        $table = "process_for_rto";
        $query = "SELECT * FROM process_for_rto WHERE rto_initiation_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
	case "RTO Inscan":
        $table = "rto_inscan";
        $query = "SELECT * FROM rto_inscan WHERE rto_initiation_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
	case "RTO Outscan":
        $table = "rto_outscan";
        $query = "SELECT * FROM rto_outscan WHERE rto_initiation_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
	case "RTO Delivered":
        $table = "rto_delivered";
        $query = "SELECT * FROM rto_delivered WHERE rto_initiation_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
        break;
        
    case "Undelivered Shipments":
        // This comprehensive query is from the old file
		$table = "courier";
		$query = "SELECT 
			cid AS 'ID',
			tracking AS 'Tracking Number',
			reference_no AS 'Reference Number',
			delivery_aggregator AS 'Delivery Aggregator',
			s_add AS 'Origin',
			r_add AS 'Destination',
			rev_name AS 'Customer Name',
			status AS 'Booking Status',
			status AS 'Delivery Status',
			last_updated AS 'Delivery Date',
			r_add AS 'Destination Address',
			comments AS 'Remarks',
			last_updated AS 'Last Updated',
			enquiry_number AS 'Enquiry Number',
			cons_no AS 'Con No',
			letra AS 'Letter Used',
			ship_name AS 'Sender Name',
			phone AS 'Sender Phone',
			s_add AS 'Sender Address',
			cc AS 'Identification Number',
			correo AS 'Sender Email Address',
			rev_name AS 'Receiver Name',
			r_phone AS 'Receiver Phone',
			telefono1 AS 'Receiver Phone 2',
			cc_r AS 'Receiver Identification',
			email AS 'Receiver Email',
			type AS 'Type',
			shipping_subtotal AS 'Subtotal Shipping',
			currency AS 'Currency',
			altura AS 'Height',
			ancho AS 'Width',
			longitud AS 'Length',
			totalpeso AS 'Total Volumetric Weight',
			invice_no AS 'Origin Office',
			qty AS 'Quantity',
			book_mode AS 'Booking Mode',
			shipping_method AS 'Shipping Method',
			mode AS 'Service Mode',
			pick_date AS 'Pickup Date',
			schedule AS 'Delivery Date (Scheduled)',
			pick_time AS 'Pickup Country',
			state AS 'Pickup State',
			ciudad AS 'Pickup City',
			zipcode AS 'Pickup Zip Code',
			paisdestino AS 'Destination Country',
			state1 AS 'Destination State',
			city1 AS 'Destination City',
			zipcode1 AS 'Destination Zip Code',
			dom_internation AS 'Domestic/International',
			comments AS 'Comments',
			enquiry_date AS 'Enquiry Date',
			payment AS 'Payment',
			paymode AS 'Pay Mode',
			officename AS 'Entry Staff Role',
			user AS 'Entry User',
			pesoreal AS 'Weight'
		FROM courier 
		WHERE status != 'Delivered' AND book_date BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'";
		break;
		
	case "Warehouses":
        // This logic is from the new file, as requested
        $filtered_warehouses = [];
        if (!empty($start_date) && !empty($end_date)) {
            $start_timestamp = strtotime($start_date . ' 00:00:00');
            $end_timestamp = strtotime($end_date . ' 23:59:59');
            
            foreach ($warehouses_list as $wh) {
                if (isset($wh['created_at']) && !empty($wh['created_at'])) {
                    $wh_timestamp = is_numeric($wh['created_at']) ? $wh['created_at'] : strtotime($wh['created_at']);
                } else {
                    $wh_timestamp = time();
                    $wh['created_at'] = date('Y-m-d H:i:s');
                }
                
                if ($wh_timestamp >= $start_timestamp && $wh_timestamp <= $end_timestamp) {
                    $filtered_warehouses[] = $wh;
                }
            }
        } else {
            $filtered_warehouses = $warehouses_list;
        }
        break;
        
	case "Inventory":
        // This logic is from the new file, as requested
        $table = "storage";
        $query = "SELECT 
            s.storage_id AS 'Storage ID',
            s.warehouse_id AS 'Warehouse ID',
            s.item_code AS 'Item Code',
            s.item_name AS 'Item Name',
            s.company_name AS 'Company Name',
            s.customer_code AS 'Customer Code',
            s.customer_name AS 'Customer Name',
            s.variation AS 'Variation',
            s.rack AS 'Rack',
            s.bin AS 'Bin',
            s.initial_qty AS 'Initial Quantity',
            s.current_qty AS 'Current Quantity',
            s.inventory_count AS 'Inventory Count',
            s.capacity AS 'Capacity',
            s.temp_range AS 'Temperature Range',
            s.batch_no AS 'Batch Number',
            s.expiry_date AS 'Expiry Date',
            s.aging_date AS 'Aging Date',
            s.responsible_person AS 'Responsible Person',
            s.special_notes AS 'Special Notes',
            s.remarks AS 'Remarks',
            s.unit_price AS 'Unit Price',
            s.selling_price AS 'Selling Price',
            s.total_value AS 'Total Value',
            DATE_FORMAT(s.created_at, '%Y-%m-%d %H:%i:%s') AS 'Created Date',
            DATE_FORMAT(s.updated_at, '%Y-%m-%d %H:%i:%s') AS 'Last Updated'
        FROM storage s 
        WHERE s.created_at BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'
        ORDER BY s.created_at DESC";
        break;
        
    case "Storage":
        // This logic is from the new file, as requested
        $table = "storage";
        if (!empty($start_date) && !empty($end_date)) {
            $query = "SELECT 
                s.storage_id AS 'Storage ID',
                s.company_name AS 'Company Name',
                s.customer_code AS 'Customer Code',
                s.customer_name AS 'Customer Name',
                s.item_code AS 'Item Code',
                s.item_name AS 'Item Name',
                s.variation AS 'Variation',
                s.warehouse_id AS 'Warehouse ID',
                s.country AS 'Country',
                s.state AS 'State',
                s.city AS 'City',
                s.area AS 'Area/Address',
                s.location AS 'Internal Location',
                s.rack AS 'Rack',
                s.bin AS 'Bin',
                s.initial_qty AS 'Initial Quantity',
                s.current_qty AS 'Current Quantity',
                s.inventory_count AS 'Inventory Count',
                s.capacity AS 'Capacity',
                s.temp_range AS 'Temperature Range',
                s.batch_no AS 'Batch Number',
                s.expiry_date AS 'Expiry Date',
                s.responsible_person AS 'Responsible Person',
                s.special_notes AS 'Special Notes',
                s.remarks AS 'Remarks',
                s.unit_price AS 'Unit Price',
                s.selling_price AS 'Selling Price',
                s.total_value AS 'Total Value',
                DATE_FORMAT(s.created_at, '%Y-%m-%d %H:%i:%s') AS 'Created Date',
                DATE_FORMAT(s.updated_at, '%Y-%m-%d %H:%i:%s') AS 'Last Updated'
            FROM storage s
            WHERE s.created_at BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'
            ORDER BY s.created_at DESC";
        } else {
            $query = "SELECT 
                s.storage_id AS 'Storage ID',
                s.company_name AS 'Company Name',
                s.customer_code AS 'Customer Code',
                s.customer_name AS 'Customer Name',
                s.item_code AS 'Item Code',
                s.item_name AS 'Item Name',
                s.variation AS 'Variation',
                s.warehouse_id AS 'Warehouse ID',
                s.country AS 'Country',
                s.state AS 'State',
                s.city AS 'City',
                s.area AS 'Area/Address',
                s.location AS 'Internal Location',
                s.rack AS 'Rack',
                s.bin AS 'Bin',
                s.initial_qty AS 'Initial Quantity',
                s.current_qty AS 'Current Quantity',
                s.inventory_count AS 'Inventory Count',
                s.capacity AS 'Capacity',
                s.temp_range AS 'Temperature Range',
                s.batch_no AS 'Batch Number',
                s.expiry_date AS 'Expiry Date',
                s.responsible_person AS 'Responsible Person',
                s.special_notes AS 'Special Notes',
                s.remarks AS 'Remarks',
                s.unit_price AS 'Unit Price',
                s.selling_price AS 'Selling Price',
                s.total_value AS 'Total Value',
                DATE_FORMAT(s.created_at, '%Y-%m-%d %H:%i:%s') AS 'Created Date',
                DATE_FORMAT(s.updated_at, '%Y-%m-%d %H:%i:%s') AS 'Last Updated'
            FROM storage s
            ORDER BY s.created_at DESC";
        }
        break;
        
    case "Products":
        // This logic is from the new file, as requested
        $table = "products";
        if (!empty($start_date) && !empty($end_date)) {
            $query = "SELECT 
                p.id AS 'Product ID',
                p.product_sku AS 'SKU',
                p.item_code AS 'Item Code',
                p.company_name AS 'Company Name',
                p.client_id AS 'Customer Code',
                p.customer_name AS 'Customer Name',
                p.product_name AS 'Product Name',
                p.category AS 'Category',
                p.brand AS 'Brand',
                p.model AS 'Model',
                p.description AS 'Description',
                CONCAT(p.base_price, ' ', p.currency) AS 'Base Price',
                CONCAT(COALESCE(p.offer_price, 0), ' ', p.currency) AS 'Offer Price',
                p.stock_quantity AS 'Stock Quantity',
                p.unit_of_measure AS 'Unit of Measure',
                p.availability_status AS 'Availability Status',
                p.warehouse_id AS 'Warehouse ID',
                p.supplier_name AS 'Supplier',
                p.warranty_period AS 'Warranty Period',
                p.manufacture_date AS 'Manufacture Date',
                p.expiration_date AS 'Expiration Date',
                CONCAT(COALESCE(p.tax_percentage, 0), '%') AS 'Tax',
                DATE_FORMAT(p.created_at, '%Y-%m-%d %H:%i:%s') AS 'Created Date',
                DATE_FORMAT(p.updated_at, '%Y-%m-%d %H:%i:%s') AS 'Last Updated'
            FROM products p
            WHERE p.created_at BETWEEN '$start_date 00:00:00' AND '$end_date 23:59:59'
            ORDER BY p.id DESC";
        } else {
            $query = "SELECT 
                p.id AS 'Product ID',
                p.product_sku AS 'SKU',
                p.item_code AS 'Item Code',
                p.company_name AS 'Company Name',
                p.client_id AS 'Customer Code',
                p.customer_name AS 'Customer Name',
                p.product_name AS 'Product Name',
                p.category AS 'Category',
                p.brand AS 'Brand',
                p.model AS 'Model',
                p.description AS 'Description',
                CONCAT(p.base_price, ' ', p.currency) AS 'Base Price',
                CONCAT(COALESCE(p.offer_price, 0), ' ', p.currency) AS 'Offer Price',
                p.stock_quantity AS 'Stock Quantity',
                p.unit_of_measure AS 'Unit of Measure',
                p.availability_status AS 'Availability Status',
                p.warehouse_id AS 'Warehouse ID',
                p.supplier_name AS 'Supplier',
                p.warranty_period AS 'Warranty Period',
                p.manufacture_date AS 'Manufacture Date',
                p.expiration_date AS 'Expiration Date',
                CONCAT(COALESCE(p.tax_percentage, 0), '%') AS 'Tax',
                DATE_FORMAT(p.created_at, '%Y-%m-%d %H:%i:%s') AS 'Created Date',
                DATE_FORMAT(p.updated_at, '%Y-%m-%d %H:%i:%s') AS 'Last Updated'
            FROM products p
            ORDER BY p.id DESC";
        }
        break;
}

// Execute the query
$shipment_data_result = null;
if ($query) {
    $shipment_data_result = mysqli_query($dbConn, $query);
}

// Export functionality
if ($export == '1') {
    if ($report_type == 'Warehouses' && !empty($filtered_warehouses)) {
        // Export warehouses to Excel
        header("Content-Type: application/vnd.ms-excel");
        header("Content-Disposition: attachment; filename=Warehouses_report_" . date("Ymd") . ".xls");

        echo "<table border='1'>";
        echo "<tr><th>ID</th><th>Warehouse Name</th><th>Country</th><th>State</th><th>City</th><th>Area/Address</th></tr>";
        
        foreach ($filtered_warehouses as $wh) {
            echo "<tr>";
            echo "<td>" . htmlspecialchars($wh['id']) . "</td>";
            echo "<td>" . htmlspecialchars($wh['name']) . "</td>";
            echo "<td>" . htmlspecialchars($wh['country']) . "</td>";
            echo "<td>" . htmlspecialchars($wh['state']) . "</td>";
            echo "<td>" . htmlspecialchars($wh['city']) . "</td>";
            echo "<td>" . htmlspecialchars($wh['area']) . "</td>";
            echo "</tr>";
        }
        echo "</table>";
        exit;
    } elseif (($report_type == 'Products' || $report_type == 'Storage' || $report_type == 'Inventory' || $report_type == 'Fulfillment') && $shipment_data_result) {
        // Export with warehouse names for applicable reports
        header("Content-Type: application/vnd.ms-excel");
        header("Content-Disposition: attachment; filename={$report_type}_report_" . date("Ymd") . ".xls");

        echo "<table border='1'>";
        
        // Get field names
        $fields = mysqli_fetch_fields($shipment_data_result);
        echo "<tr>";
        foreach ($fields as $field) {
            if ($field->name != 'Warehouse ID') {
                echo "<th>" . htmlspecialchars($field->name) . "</th>";
            } else {
                echo "<th>Warehouse</th>";
            }
        }
        echo "</tr>";

        mysqli_data_seek($shipment_data_result, 0);
        while ($row = mysqli_fetch_assoc($shipment_data_result)) {
            echo "<tr>";
            foreach ($row as $key => $value) {
                if ($key == 'Warehouse ID') {
                    $warehouse_name = isset($warehouse_id_lookup[$value]) ? $warehouse_id_lookup[$value] : 'Not Assigned';
                    echo "<td>" . htmlspecialchars($warehouse_name) . "</td>";
                } else {
                    echo "<td>" . htmlspecialchars($value) . "</td>";
                }
            }
            echo "</tr>";
        }
        echo "</table>";
        exit;
    } elseif ($shipment_data_result) {
        // Generic export for other report types
        header("Content-Type: application/vnd.ms-excel");
        header("Content-Disposition: attachment; filename={$report_type}_report_" . date("Ymd") . ".xls");

        echo "<table border='1'>";

        $fields = mysqli_fetch_fields($shipment_data_result);
        echo "<tr>";
        foreach ($fields as $field) {
            $header = $column_mapping[$field->name] ?? $field->name;
            echo "<th>" . htmlspecialchars($header) . "</th>";
        }
        echo "</tr>";

        mysqli_data_seek($shipment_data_result, 0);
        while ($row = mysqli_fetch_assoc($shipment_data_result)) {
            echo "<tr>";
            foreach ($row as $value) {
                echo "<td>" . htmlspecialchars($value) . "</td>";
            }
            echo "</tr>";
        }

        echo "</table>";
        exit;
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo $_SESSION['ge_cname']; ?> | Advanced Reports</title>
  <meta name="description" content="<?php echo $_SESSION['ge_description']; ?>"/>
  <meta name="keywords" content="<?php echo $_SESSION['ge_keywords']; ?>" />
  <meta name="author" content="Jaomweb">	
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  
  <link rel="shortcut icon" type="image/png" href="img/favicon.png"/>
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.css" type="text/css" />
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css" type="text/css" />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  
  <style>
    /* Modern Beautiful Styling */
    :root {
        --primary-dark: #0A2342;
        --primary-blue: #2C5F8D;
        --accent-blue: #3498db;
        --accent-cyan: #00D4FF;
        --success: #27ae60;
        --warning: #f39c12;
        --danger: #e74c3c;
        --light-bg: #f8f9fa;
        --card-shadow: 0 10px 40px rgba(10, 35, 66, 0.12);
        --card-hover-shadow: 0 15px 50px rgba(10, 35, 66, 0.18);
        --gradient-primary: linear-gradient(135deg, #0A2342 0%, #2C5F8D 50%, #3498db 100%);
        --gradient-accent: linear-gradient(135deg, #00D4FF 0%, #3498db 100%);
    }
    
    * {
        margin: 0;
        padding: 0;
        box-sizing: border-box;
    }
    
    body {
        font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
        background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
        background-attachment: fixed;
        min-height: 100vh;
        padding: 0;
        margin: 0;
    }
    
    /* Top Navigation Bar */
    .top-navbar {
        background: var(--gradient-primary);
        box-shadow: 0 4px 20px rgba(10, 35, 66, 0.2);
        padding: 0;
        position: sticky;
        top: 0;
        z-index: 1000;
    }
    
    .top-navbar .container-fluid {
        padding: 15px 30px;
    }
    
    .navbar-brand-custom {
        display: flex;
        align-items: center;
        gap: 15px;
        color: white;
        font-size: 24px;
        font-weight: 800;
        text-decoration: none;
    }
    
    .navbar-brand-custom:hover {
        color: var(--accent-cyan);
        text-decoration: none;
    }
    
    .navbar-brand-custom i {
        font-size: 28px;
    }
    
    .navbar-user-info {
        display: flex;
        align-items: center;
        gap: 20px;
        color: white;
    }
    
    .user-badge {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px 20px;
        background: rgba(255, 255, 255, 0.15);
        border-radius: 25px;
        backdrop-filter: blur(10px);
    }
    
    .user-badge i {
        font-size: 20px;
    }
    
    .logout-btn {
        padding: 10px 25px;
        background: rgba(255, 255, 255, 0.2);
        border: 2px solid white;
        border-radius: 25px;
        color: white;
        text-decoration: none;
        font-weight: 600;
        transition: all 0.3s ease;
        display: inline-flex;
        align-items: center;
        gap: 8px;
    }
    
    .logout-btn:hover {
        background: white;
        color: var(--primary-dark);
        text-decoration: none;
        transform: translateY(-2px);
        box-shadow: 0 4px 15px rgba(255, 255, 255, 0.3);
    }
    
    /* Main Container */
    .main-container {
        max-width: 1400px;
        margin: 0 auto;
        padding: 30px 20px;
    }
    
    /* Beautiful Header Card */
    .report-header-card {
        background: var(--gradient-primary);
        border-radius: 20px;
        padding: 40px;
        margin-bottom: 30px;
        box-shadow: var(--card-shadow);
        color: white;
        position: relative;
        overflow: hidden;
    }
    
    .report-header-card::before {
        content: '';
        position: absolute;
        top: -50%;
        right: -20%;
        width: 500px;
        height: 500px;
        background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
        border-radius: 50%;
    }
    
    .report-header-card h2 {
        color: white;
        font-weight: 800;
        font-size: 32px;
        margin: 0 0 10px 0;
        position: relative;
        z-index: 1;
    }
    
    .report-header-card p {
        color: rgba(255,255,255,0.9);
        font-size: 16px;
        margin: 0;
        position: relative;
        z-index: 1;
    }
    
    /* Beautiful Filter Card */
    .modern-filter-card {
        background: white;
        border-radius: 20px;
        padding: 0;
        margin-bottom: 30px;
        box-shadow: var(--card-shadow);
        overflow: hidden;
        transition: all 0.3s ease;
    }
    
    .modern-filter-card:hover {
        box-shadow: var(--card-hover-shadow);
        transform: translateY(-2px);
    }
    
    .filter-card-header {
        background: var(--gradient-primary);
        padding: 25px 30px;
        border-bottom: none;
    }
    
    .filter-card-header h4 {
        color: white;
        margin: 0;
        font-weight: 700;
        font-size: 20px;
        display: flex;
        align-items: center;
        gap: 10px;
    }
    
    .filter-card-header h4 i {
        font-size: 24px;
    }
    
    .filter-card-body {
        padding: 30px;
        background: linear-gradient(to bottom, #ffffff 0%, #f8f9fa 100%);
    }
    
    /* Modern Form Controls */
    .modern-form-group {
        margin-bottom: 20px;
        position: relative;
    }
    
    .modern-form-group label {
        font-weight: 600;
        color: var(--primary-dark);
        margin-bottom: 8px;
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 13px;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }
    
    .modern-form-group label i {
        color: var(--accent-blue);
        font-size: 16px;
    }
    
    .modern-input, .modern-select {
        width: 100%;
        padding: 14px 18px 14px 45px;
        border: 2px solid #e1e8ed;
        border-radius: 12px;
        font-size: 15px;
        transition: all 0.3s ease;
        background: white;
        color: #2c3e50;
        font-weight: 500;
    }
    
    .modern-input:focus, .modern-select:focus {
        outline: none;
        border-color: var(--accent-blue);
        box-shadow: 0 0 0 4px rgba(52, 152, 219, 0.1);
        transform: translateY(-1px);
    }
    
    .modern-input::placeholder {
        color: #95a5a6;
        font-weight: 400;
    }
    
    .input-icon {
        position: absolute;
        left: 16px;
        top: 42px;
        color: var(--accent-blue);
        font-size: 18px;
        pointer-events: none;
    }
    
    /* Beautiful Buttons */
    .modern-btn {
        padding: 14px 28px;
        border: none;
        border-radius: 12px;
        font-weight: 600;
        font-size: 15px;
        cursor: pointer;
        transition: all 0.3s ease;
        display: inline-flex;
        align-items: center;
        gap: 10px;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        box-shadow: 0 4px 15px rgba(0,0,0,0.1);
    }
    
    .modern-btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(0,0,0,0.15);
    }
    
    .modern-btn:active {
        transform: translateY(0);
    }
    
    .btn-generate {
        background: var(--gradient-accent);
        color: white;
        width: 100%;
        justify-content: center;
        font-size: 16px;
        padding: 16px;
    }
    
    .btn-apply {
        background: linear-gradient(135deg, #27ae60 0%, #2ecc71 100%);
        color: white;
    }
    
    .btn-reset {
        background: linear-gradient(135deg, #95a5a6 0%, #bdc3c7 100%);
        color: white;
    }
    
    .btn-export {
        background: linear-gradient(135deg, #f39c12 0%, #f1c40f 100%);
        color: white;
        text-decoration: none;
    }
    
    .btn-export:hover {
        color: white;
        text-decoration: none;
    }
    
    /* Advanced Filter Section */
    .advanced-filter-section {
        background: white;
        border-radius: 20px;
        padding: 0;
        margin-top: 25px;
        box-shadow: var(--card-shadow);
        overflow: hidden;
    }
    
    .advanced-filter-header {
        background: linear-gradient(135deg, #8e44ad 0%, #3498db 100%);
        padding: 20px 30px;
        color: white;
        display: flex;
        justify-content: space-between;
        align-items: center;
    }
    
    .advanced-filter-header h5 {
        margin: 0;
        font-weight: 700;
        font-size: 18px;
        display: flex;
        align-items: center;
        gap: 10px;
    }
    
    .filter-count-badge {
        background: rgba(255,255,255,0.25);
        padding: 6px 14px;
        border-radius: 20px;
        font-size: 14px;
        font-weight: 600;
        backdrop-filter: blur(10px);
    }
    
    .advanced-filter-body {
        padding: 30px;
        background: #f8f9fa;
    }
    
    /* Table Styling */
    .modern-table-container {
        background: white;
        border-radius: 20px;
        padding: 0;
        margin-top: 30px;
        box-shadow: var(--card-shadow);
        overflow: hidden;
    }
    
    .table-header-section {
        background: var(--gradient-primary);
        padding: 25px 30px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        flex-wrap: wrap;
        gap: 15px;
    }
    
    .table-header-section h4 {
        color: white;
        margin: 0;
        font-weight: 700;
        font-size: 20px;
    }
    
    .table-responsive {
        border-radius: 0 0 20px 20px;
        overflow-x: auto;
    }
    
    .table-striped > thead > tr > th {
        background: var(--primary-dark) !important;
        color: white !important;
        font-weight: 600;
        text-transform: uppercase;
        font-size: 12px;
        letter-spacing: 0.5px;
        padding: 18px 12px !important;
        border: none !important;
        white-space: nowrap;
    }
    
    .table-striped > tbody > tr {
        transition: all 0.2s ease;
    }
    
    .table-striped > tbody > tr:hover {
        background-color: #e3f2fd !important;
        transform: scale(1.01);
        box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    }
    
    .table-striped > tbody > tr > td {
        padding: 15px 12px !important;
        vertical-align: middle;
        font-size: 14px;
        border-color: #ecf0f1 !important;
    }
    
    /* Alert Messages */
    .alert {
        border: none;
        border-radius: 12px;
        padding: 18px 24px;
        font-weight: 500;
        box-shadow: 0 4px 15px rgba(0,0,0,0.08);
        margin-bottom: 25px;
    }
    
    .alert-info {
        background: linear-gradient(135deg, #e3f2fd 0%, #bbdefb 100%);
        color: #1565c0;
        border-left: 4px solid #2196F3;
    }
    
    .alert-warning {
        background: linear-gradient(135deg, #fff3e0 0%, #ffe0b2 100%);
        color: #e65100;
        border-left: 4px solid #ff9800;
    }
    
    /* Stats Badge */
    .stats-badge {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 10px 18px;
        background: rgba(255,255,255,0.2);
        border-radius: 25px;
        color: white;
        font-weight: 600;
        font-size: 14px;
        backdrop-filter: blur(10px);
    }
    
    .stats-badge i {
        font-size: 18px;
    }
    
    /* Warehouse Badge */
    .warehouse-badge {
        display: inline-block;
        padding: 6px 12px;
        background: var(--gradient-accent);
        color: white;
        border-radius: 8px;
        font-weight: 600;
        font-size: 13px;
    }
    
    /* Responsive Design */
    @media (max-width: 768px) {
        .report-header-card {
            padding: 25px;
        }
        
        .report-header-card h2 {
            font-size: 24px;
        }
        
        .filter-card-body, .advanced-filter-body {
            padding: 20px;
        }
        
        .modern-btn {
            width: 100%;
            justify-content: center;
            margin-bottom: 10px;
        }
    }
    
    /* Animation */
    @keyframes fadeInUp {
        from {
            opacity: 0;
            transform: translateY(20px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }
    
    .animate-in {
        animation: fadeInUp 0.6s ease-out;
    }
    
    /* Loading State */
    .loading-overlay {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(10, 35, 66, 0.9);
        display: none;
        justify-content: center;
        align-items: center;
        z-index: 9999;
    }
    
    .loading-spinner {
        border: 4px solid rgba(255,255,255,0.3);
        border-top: 4px solid white;
        border-radius: 50%;
        width: 60px;
        height: 60px;
        animation: spin 1s linear infinite;
    }
    
    @keyframes spin {
        0% { transform: rotate(0deg); }
        100% { transform: rotate(360deg); }
    }
  </style>
</head>
<body>

<!-- Top Navigation Bar -->
<nav class="top-navbar">
  <div class="container-fluid">
    <div style="display: flex; justify-content: space-between; align-items: center;">
      <a href="dashboard.php" class="navbar-brand-custom">
        <i class="fa fa-cube"></i>
        <span>ABRA GROUP</span>
      </a>
      <div class="navbar-user-info">
        <div class="user-badge">
          <i class="fa fa-user-circle"></i>
          <span><?php echo htmlspecialchars($_SESSION['user_name']); ?></span>
        </div>
        <a href="?action=logout" class="logout-btn">
          <i class="fa fa-sign-out"></i>
          Logout
        </a>
      </div>
    </div>
  </div>
</nav>

<!-- Main Content Container -->
<div class="main-container">
  
  <!-- Beautiful Header Card -->
  <div class="report-header-card animate-in">
    <h2><i class="fa fa-chart-line"></i> Advanced Logistics Reports</h2>
    <p>Generate comprehensive reports with powerful filtering capabilities</p>
    <div style="margin-top: 20px;">
      <span class="stats-badge">
        <i class="fa fa-database"></i>
        <?php echo count($warehouses_list); ?> Warehouses
      </span>
      <span class="stats-badge" style="margin-left: 10px;">
        <i class="fa fa-calendar"></i>
        <?php echo date('F d, Y'); ?>
      </span>
    </div>
  </div>

  <!-- Main Filter Card -->
  <div class="modern-filter-card animate-in">
    <div class="filter-card-header">
      <h4><i class="fa fa-cog"></i> Report Configuration</h4>
    </div>
    <div class="filter-card-body">
      <form action="shipment-reports.php" method="GET" id="reportFilterForm">
        <div class="row">
          <div class="col-md-6">
            <div class="modern-form-group">
              <label><i class="fa fa-file-text"></i> Report Type</label>
              <i class="fa fa-file-alt input-icon"></i>
              <select class="modern-select" name="report_type" required>
                <option value="">-- Select Report Type --</option>
                <option value="Customer Orders" <?php echo ($report_type == "Customer Orders") ? 'selected' : ''; ?>>Customer Orders</option>
                <option value="Fulfillment" <?php echo ($report_type == "Fulfillment") ? 'selected' : ''; ?>>Fulfillment</option>
                <option value="Inscan" <?php echo ($report_type == "Inscan") ? 'selected' : ''; ?>>Inscan</option>
                <option value="Outscan" <?php echo ($report_type == "Outscan") ? 'selected' : ''; ?>>Outscan</option>
                <option value="Delivered" <?php echo ($report_type == "Delivered") ? 'selected' : ''; ?>>Delivered</option>
                <option value="RTS" <?php echo ($report_type == "RTS") ? 'selected' : ''; ?>>RTS</option>
                <option value="RTO" <?php echo ($report_type == "RTO") ? 'selected' : ''; ?>>RTO</option>
                <option value="Cancelled Shipments" <?php echo ($report_type == "Cancelled Shipments") ? 'selected' : ''; ?>>Cancelled Shipments</option>
                <option value="Process for RTO" <?php echo ($report_type == "Process for RTO") ? 'selected' : ''; ?>>Process for RTO</option>
                <option value="RTO Inscan" <?php echo ($report_type == "RTO Inscan") ? 'selected' : ''; ?>>RTO Inscan</option>
                <option value="RTO Outscan" <?php echo ($report_type == "RTO Outscan") ? 'selected' : ''; ?>>RTO Outscan</option>
                <option value="RTO Delivered" <?php echo ($report_type == "RTO Delivered") ? 'selected' : ''; ?>>RTO Delivered</option>
                <option value="Undelivered Shipments" <?php echo ($report_type == "Undelivered Shipments") ? 'selected' : ''; ?>>Undelivered Shipments</option>
                <option value="Warehouses" <?php echo ($report_type == "Warehouses") ? 'selected' : ''; ?>>Warehouses</option>
                <option value="Inventory" <?php echo ($report_type == "Inventory") ? 'selected' : ''; ?>>Inventory</option>
                <option value="Storage" <?php echo ($report_type == "Storage") ? 'selected' : ''; ?>>Storage</option>
                <option value="Products" <?php echo ($report_type == "Products") ? 'selected' : ''; ?>>Products</option>
              </select>
            </div>
          </div>
          <div class="col-md-3">
            <div class="modern-form-group">
              <label><i class="fa fa-calendar-check"></i> Start Date</label>
              <i class="fa fa-calendar input-icon"></i>
              <input type="date" name="start_date" class="modern-input" value="<?php echo htmlspecialchars($start_date); ?>"/>
            </div>
          </div>
          <div class="col-md-3">
            <div class="modern-form-group">
              <label><i class="fa fa-calendar-times"></i> End Date</label>
              <i class="fa fa-calendar input-icon"></i>
              <input type="date" name="end_date" class="modern-input" value="<?php echo htmlspecialchars($end_date); ?>"/>
            </div>
          </div>
        </div>
        
        <div class="row" style="margin-top: 10px;">
          <div class="col-md-12">
            <button type="submit" class="modern-btn btn-generate">
              <i class="fa fa-rocket"></i> Generate Report
            </button>
          </div>
        </div>
      </form>
    </div>
  </div>
  
  <!-- Advanced Filters Section -->
  <div class="advanced-filter-section animate-in">
    <div class="advanced-filter-header">
      <h5><i class="fa fa-sliders-h"></i> Advanced Filters</h5>
      <span class="filter-count-badge" id="filterResultCount">
        <i class="fa fa-filter"></i> All Records
      </span>
    </div>
    <div class="advanced-filter-body">
      <div class="row">
        <div class="col-md-3 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-warehouse"></i> Warehouse</label>
            <i class="fa fa-building input-icon"></i>
            <select id="filterWarehouse" class="modern-select">
              <option value="">All Warehouses</option>
              <?php foreach ($warehouse_id_lookup as $wh_id => $wh_name): ?>
                <option value="<?php echo htmlspecialchars($wh_name); ?>"><?php echo htmlspecialchars($wh_name); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
        </div>
        <div class="col-md-2 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-globe"></i> Country</label>
            <i class="fa fa-globe-americas input-icon"></i>
            <input type="text" id="filterCountry" class="modern-input" placeholder="e.g., India">
          </div>
        </div>
        <div class="col-md-2 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-map"></i> State</label>
            <i class="fa fa-map-marked input-icon"></i>
            <input type="text" id="filterState" class="modern-input" placeholder="e.g., Karnataka">
          </div>
        </div>
        <div class="col-md-2 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-city"></i> City</label>
            <i class="fa fa-map-pin input-icon"></i>
            <input type="text" id="filterCity" class="modern-input" placeholder="e.g., Bangalore">
          </div>
        </div>
        <div class="col-md-3 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-home"></i> Area/Address</label>
            <i class="fa fa-location-arrow input-icon"></i>
            <input type="text" id="filterArea" class="modern-input" placeholder="Search area...">
          </div>
        </div>
      </div>
      
      <div class="row" style="margin-top: 5px;">
        <div class="col-md-3 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-user"></i> Customer Name</label>
            <i class="fa fa-user-circle input-icon"></i>
            <input type="text" id="filterCustomer" class="modern-input" placeholder="Search customer...">
          </div>
        </div>
        <div class="col-md-3 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-building"></i> Company Name</label>
            <i class="fa fa-briefcase input-icon"></i>
            <input type="text" id="filterCompany" class="modern-input" placeholder="Search company...">
          </div>
        </div>
        <div class="col-md-3 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-barcode"></i> Tracking/ID</label>
            <i class="fa fa-hashtag input-icon"></i>
            <input type="text" id="filterTracking" class="modern-input" placeholder="Search ID...">
          </div>
        </div>
        <div class="col-md-3 col-sm-6">
          <div class="modern-form-group">
            <label><i class="fa fa-info-circle"></i> Status</label>
            <i class="fa fa-check-circle input-icon"></i>
            <input type="text" id="filterStatus" class="modern-input" placeholder="e.g., Fulfilled">
          </div>
        </div>
      </div>
      
      <div class="row" style="margin-top: 15px;">
        <div class="col-md-12 text-right">
          <button type="button" id="applyFilters" class="modern-btn btn-apply">
            <i class="fa fa-check"></i> Apply Filters
          </button>
          <button type="button" id="resetFilters" class="modern-btn btn-reset">
            <i class="fa fa-redo"></i> Reset
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- Results Section -->
  <?php if (!empty($report_type)): ?>
    <div class="modern-table-container animate-in">
      <div class="table-header-section">
        <h4><?php echo htmlspecialchars($report_type); ?> Report</h4>
        <a href="<?php echo $_SERVER['REQUEST_URI'];?>&export=1" class="modern-btn btn-export">
          <i class="fa fa-file-excel"></i> Export to Excel
        </a>
      </div>
      
      <div class="table-responsive">
        <?php
        if ($report_type == 'Warehouses') {
            // Display warehouses data
            if (!empty($filtered_warehouses)) {
                echo '<table class="table table-striped b-t b-b">';
                echo '<thead><tr>';
                echo '<th>ID</th><th>Warehouse Name</th><th>Country</th><th>State</th><th>City</th><th>Area/Address</th>';
                echo '</tr></thead>';
                echo '<tbody>';
                
                foreach ($filtered_warehouses as $wh) {
                    echo '<tr>';
                    echo '<td><span class="label label-primary">' . htmlspecialchars($wh['id']) . '</span></td>';
                    echo '<td><strong>' . htmlspecialchars($wh['name']) . '</strong></td>';
                    echo '<td>' . htmlspecialchars($wh['country']) . '</td>';
                    echo '<td>' . htmlspecialchars($wh['state']) . '</td>';
                    echo '<td>' . htmlspecialchars($wh['city']) . '</td>';
                    echo '<td>' . htmlspecialchars($wh['area']) . '</td>';
                    echo '</tr>';
                }
                
                echo '</tbody></table>';
            } else {
                if (!empty($start_date) && !empty($end_date)) {
                    echo "<div class='alert alert-info'><i class='fa fa-info-circle'></i> No warehouses found in the selected date range.</div>";
                } else {
                    echo "<div class='alert alert-warning'><i class='fa fa-exclamation-triangle'></i> Please select a date range to view warehouses.</div>";
                }
            }
        } elseif (($report_type == 'Products' || $report_type == 'Storage' || $report_type == 'Inventory' || $report_type == 'Fulfillment') && $shipment_data_result && mysqli_num_rows($shipment_data_result) > 0) {
            // Special handling for Products, Storage, Inventory, and Fulfillment to show warehouse names
            echo '<table class="table table-striped b-t b-b">';
            echo '<thead><tr>';

            mysqli_data_seek($shipment_data_result, 0);
            while ($field = mysqli_fetch_field($shipment_data_result)) {
                if ($field->name != 'Warehouse ID') {
                    echo "<th>" . htmlspecialchars($field->name) . "</th>";
                } else {
                    echo "<th>Warehouse</th>";
                }
            }

            echo '</tr></thead>';
            echo '<tbody>';

            mysqli_data_seek($shipment_data_result, 0);
            while ($row = mysqli_fetch_assoc($shipment_data_result)) {
                echo '<tr>';
                foreach ($row as $key => $value) {
                    if ($key == 'Warehouse ID') {
                        $warehouse_name = isset($warehouse_id_lookup[$value]) ? $warehouse_id_lookup[$value] : 'Not Assigned';
                        echo "<td><span class='warehouse-badge'>" . htmlspecialchars($warehouse_name) . "</span></td>";
                    } else {
                        echo "<td>" . htmlspecialchars($value) . "</td>";
                    }
                }
                echo '</tr>';
            }

            echo '</tbody></table>';
        } elseif ($shipment_data_result && mysqli_num_rows($shipment_data_result) > 0) {
            echo '<table class="table table-striped b-t b-b">';
            echo '<thead><tr>';

            mysqli_data_seek($shipment_data_result, 0);
            while ($field = mysqli_fetch_field($shipment_data_result)) {
                $header = $column_mapping[$field->name] ?? $field->name;
                echo "<th>" . htmlspecialchars($header) . "</th>";
            }
            
            // Add Download Ticket column only for certain report types
            $show_ticket_column = in_array($report_type, ['Customer Orders', 'Delivered', 'Undelivered Shipments']);
            if ($show_ticket_column) {
                echo "<th>Ticket</th>";
            }

            echo '</tr></thead>';
            echo '<tbody>';

            mysqli_data_seek($shipment_data_result, 0);
            while ($row = mysqli_fetch_assoc($shipment_data_result)) {
                echo '<tr>';
                foreach ($row as $value) {
                    echo "<td>" . htmlspecialchars($value) . "</td>";
                }
                
                // Add ticket download link for applicable reports
                if ($show_ticket_column) {
                    $ticket_id = isset($row['ID']) ? $row['ID'] : (isset($row['cid']) ? $row['cid'] : '');
                    
                    echo '<td align="center">
                        <a title="Download Ticket" target="_blank" href="print-invoice/ticket-print.php?cid=' . codificar($ticket_id) . '" class="btn btn-sm btn-info">
                            <i class="fa fa-download"></i>
                        </a>
                    </td>';
                }
                echo '</tr>';
            }

            echo '</tbody></table>';
        } else {
            if (!empty($start_date) && !empty($end_date)) {
                echo "<div class='alert alert-info' style='margin: 20px;'><i class='fa fa-info-circle'></i> No data found for the selected date range.</div>";
            } else {
                 if (!empty($report_type)) {
                    echo "<div class='alert alert-warning' style='margin: 20px;'><i class='fa fa-exclamation-triangle'></i> Please select a date range to generate the report.</div>";
                 }
            }
        }
        ?>
      </div>
    </div>
  <?php endif; ?>

</div>

<?php include("footer.php"); ?>

<div class="loading-overlay" id="loadingOverlay">
  <div class="loading-spinner"></div>
</div>

<script src="https://code.jquery.com/jquery-3.3.1.min.js"></script>
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>

<script>
$(document).ready(function() {
    // Show loading overlay on form submit
    $('#reportFilterForm').on('submit', function() {
        $('#loadingOverlay').css('display', 'flex');
    });
    
    // Advanced filtering functionality
    const filters = {
        warehouse: $('#filterWarehouse'),
        country: $('#filterCountry'),
        state: $('#filterState'),
        city: $('#filterCity'),
        area: $('#filterArea'),
        customer: $('#filterCustomer'),
        company: $('#filterCompany'),
        tracking: $('#filterTracking'),
        status: $('#filterStatus')
    };
    
    const dataTable = $('.table.table-striped tbody');
    const allRows = dataTable.find('tr').not('#noResultsRow');
    const totalRows = allRows.length;
    
    function applyFilters() {
        if (allRows.length === 0) return;
        
        const filterValues = {
            warehouse: filters.warehouse.val().toLowerCase(),
            country: filters.country.val().toLowerCase(),
            state: filters.state.val().toLowerCase(),
            city: filters.city.val().toLowerCase(),
            area: filters.area.val().toLowerCase(),
            customer: filters.customer.val().toLowerCase(),
            company: filters.company.val().toLowerCase(),
            tracking: filters.tracking.val().toLowerCase(),
            status: filters.status.val().toLowerCase()
        };
        
        let visibleCount = 0;
        
        allRows.each(function() {
            const row = $(this);
            const rowText = row.text().toLowerCase();
            
            let shouldShow = true;
            
            if (filterValues.warehouse && !row.find('td:contains("' + filterValues.warehouse + '")').length) shouldShow = false;
            if (filterValues.country && !row.find('td:contains("' + filterValues.country + '")').length) shouldShow = false;
            if (filterValues.state && !row.find('td:contains("' + filterValues.state + '")').length) shouldShow = false;
            if (filterValues.city && !row.find('td:contains("' + filterValues.city + '")').length) shouldShow = false;
            
            if (filterValues.area && rowText.indexOf(filterValues.area) === -1) shouldShow = false;
            if (filterValues.customer && rowText.indexOf(filterValues.customer) === -1) shouldShow = false;
            if (filterValues.company && rowText.indexOf(filterValues.company) === -1) shouldShow = false;
            if (filterValues.tracking && rowText.indexOf(filterValues.tracking) === -1) shouldShow = false;
            if (filterValues.status && rowText.indexOf(filterValues.status) === -1) shouldShow = false;
            
            if (shouldShow) {
                row.show();
                visibleCount++;
            } else {
                row.hide();
            }
        });
        
        // Update result count
        $('#filterResultCount').html(
            '<i class="fa fa-filter"></i> Showing ' + visibleCount + ' of ' + totalRows
        );
        
        // Show "no results" message if needed
        if (visibleCount === 0 && totalRows > 0) {
            const colspan = allRows.first().find('td').length;
            if ($('#noResultsRow').length === 0) {
                dataTable.append(
                    '<tr id="noResultsRow"><td colspan="' + colspan + 
                    '" class="text-center" style="padding: 40px;"><div style="font-size: 48px; color: #bdc3c7; margin-bottom: 15px;"><i class="fa fa-search"></i></div><h4 style="color: #7f8c8d; font-weight: 600;">No records match your filter criteria</h4><p style="color: #95a5a6;">Try adjusting or clearing your filters to see more results</p></td></tr>'
                );
            } else {
                $('#noResultsRow').show();
            }
        } else {
            $('#noResultsRow').hide();
        }
    }
    
    // Apply filters button
    $('#applyFilters').on('click', function() {
        $(this).html('<i class="fa fa-spinner fa-spin"></i> Applying...');
        setTimeout(function() {
            applyFilters();
            $('#applyFilters').html('<i class="fa fa-check"></i> Apply Filters');
        }, 300);
    });
    
    // Reset filters button
    $('#resetFilters').on('click', function() {
        $.each(filters, function(key, element) {
            element.val('');
        });
        allRows.show();
        $('#noResultsRow').hide();
        $('#filterResultCount').html(
            '<i class="fa fa-filter"></i> Showing ' + totalRows + ' of ' + totalRows
        );
    });
    
    // Apply filters on Enter key in text inputs
    $('input[type="text"]', '.advanced-filter-body').on('keypress', function(e) {
        if (e.which === 13) {
            e.preventDefault();
            applyFilters();
        }
    });
    
    // Initialize count on page load
    if (totalRows > 0) {
        $('#filterResultCount').html(
            '<i class="fa fa-filter"></i> Showing ' + totalRows + ' of ' + totalRows
        );
    }
    
    // Add smooth scroll to results
    $('button[type="submit"]').on('click', function() {
        setTimeout(function() {
            if ($('.modern-table-container').length > 0) {
                $('html, body').animate({
                    scrollTop: $('.modern-table-container').offset().top - 100
                }, 800);
            }
        }, 100);
    });
});
</script>

</body>
</html>