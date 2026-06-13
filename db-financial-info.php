<?php
// =========================================================================
// DB FINANCIAL INFO — Project Costing & Billing Module
// Navy Blue Gradient Theme — Full CRM System
// =========================================================================

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('memory_limit', '256M');
ini_set('post_max_size', '50M');
ini_set('upload_max_filesize', '50M');

session_start();

$host = "localhost";
$user = "royaldxd_user";
$pass = "meg_layout312";
$db   = "royaldxd_abra_crm";

$con = new mysqli($host, $user, $pass, $db);
if ($con->connect_error) die("Connection failed: " . $con->connect_error);
$con->set_charset("utf8mb4");

$userName = $_SESSION['user_name'] ?? 'Admin';

// =========================================================================
// FETCH CRM PERMISSIONS (Global Role-Based)
// =========================================================================
$currentUserName = $_SESSION['user_name'] ?? '';
$user_id = 0; 
$permissions = [];
if (isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Administrator') {
    $r = mysqli_query($con, "SELECT cid FROM manager_admin WHERE name='".mysqli_real_escape_string($con, $currentUserName)."' LIMIT 1");
    if ($r && $rw = mysqli_fetch_array($r)) $user_id = $rw['cid'];
} elseif (isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Employee') {
    $r = mysqli_query($con, "SELECT cid FROM manager_user WHERE name='".mysqli_real_escape_string($con, $currentUserName)."' LIMIT 1");
    if ($r && $rw = mysqli_fetch_array($r)) $user_id = $rw['cid'];
}
if ($user_id > 0) {
    $stmt = $con->prepare("SELECT section_name, can_access FROM manager_permissions WHERE user_id=?");
    if ($stmt) {
        $stmt->bind_param("i", $user_id); 
        $stmt->execute();
        $result = $stmt->get_result();
        while ($row = $result->fetch_assoc()) $permissions[$row['section_name']] = $row['can_access'];
        $stmt->close();
    }
}
$is_admin_user = (isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Administrator');
$has_full_access = $is_admin_user;

$dashboard_url = 'db-dashboard.php';

$can_view_dash      = ($has_full_access || (!empty($permissions['adb_proj_fin_dash']) && $permissions['adb_proj_fin_dash'] == 1));
$can_view_budgets   = ($has_full_access || (!empty($permissions['adb_proj_fin_budg']) && $permissions['adb_proj_fin_budg'] == 1));
$can_view_expenses  = ($has_full_access || (!empty($permissions['adb_proj_fin_exp']) && $permissions['adb_proj_fin_exp'] == 1));
$can_view_payments  = ($has_full_access || (!empty($permissions['adb_proj_fin_pay']) && $permissions['adb_proj_fin_pay'] == 1));
$can_view_reports   = ($has_full_access || (!empty($permissions['adb_proj_fin_rep']) && $permissions['adb_proj_fin_rep'] == 1));

// Legacy compatibility
$can_upload_expenses = $can_view_expenses;
$can_add_payments    = $can_view_payments;

// =========================================================================
// DATABASE MIGRATIONS (Auto Create/Update Tables)
// =========================================================================
// Add budget columns to stages if they don't exist
$res = $con->query("SHOW COLUMNS FROM `crm_construction_stages` LIKE 'allocated_budget'");
if ($res && $res->num_rows == 0) {
    $con->query("ALTER TABLE `crm_construction_stages` ADD COLUMN `allocated_budget` DECIMAL(15,2) DEFAULT 0.00");
}
$res2 = $con->query("SHOW COLUMNS FROM `crm_construction_stages` LIKE 'customer_billing_amount'");
if ($res2 && $res2->num_rows == 0) {
    $con->query("ALTER TABLE `crm_construction_stages` ADD COLUMN `customer_billing_amount` DECIMAL(15,2) DEFAULT 0.00");
}

$res3 = $con->query("SHOW COLUMNS FROM `crm_project_expenses` LIKE 'task_id'");
if ($res3 && $res3->num_rows == 0) {
    $con->query("ALTER TABLE `crm_project_expenses` ADD COLUMN `task_id` INT(11) DEFAULT NULL AFTER `stage_id`");
}

$con->query("CREATE TABLE IF NOT EXISTS `crm_expense_categories` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `category_name` VARCHAR(100) NOT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$cc = $con->query("SELECT count(*) as cnt FROM crm_expense_categories")->fetch_assoc()['cnt'];
if ($cc == 0) {
    $con->query("INSERT INTO crm_expense_categories (category_name) VALUES ('Labour / Wages'), ('Materials (Cement, Sand, Steel etc)'), ('Equipment Hire (JCB, Scaffolding)'), ('Miscellaneous / Transport')");
}

// Project Expenses Table
$con->query("
CREATE TABLE IF NOT EXISTS `crm_project_expenses` (
    `id`               INT(11) NOT NULL AUTO_INCREMENT,
    `project_id`       INT(11) NOT NULL,
    `stage_id`         INT(11) DEFAULT NULL,
    `expense_category` VARCHAR(100) NOT NULL,
    `expense_date`     DATE DEFAULT NULL,
    `amount`           DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `description`      TEXT DEFAULT NULL,
    `proof_file`       VARCHAR(500) DEFAULT NULL,
    `added_by`         VARCHAR(100) DEFAULT NULL,
    `status`           VARCHAR(50) DEFAULT 'Approved',
    `manager_reason`   TEXT DEFAULT NULL,
    `created_at`       DATETIME DEFAULT CURRENT_TIMESTAMP,
    `updated_at`       DATETIME DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_project_id` (`project_id`),
    KEY `idx_stage_id` (`stage_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// Customer Payments Table
$con->query("
CREATE TABLE IF NOT EXISTS `crm_project_payments` (
    `id`               INT(11) NOT NULL AUTO_INCREMENT,
    `project_id`       INT(11) NOT NULL,
    `stage_id`         INT(11) DEFAULT NULL,
    `payment_type`     VARCHAR(50) DEFAULT 'Stage Payment', /* Advance, Stage Payment, Final */
    `payment_date`     DATE DEFAULT NULL,
    `amount`           DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `payment_mode`     VARCHAR(50) DEFAULT NULL,
    `reference_no`     VARCHAR(100) DEFAULT NULL,
    `notes`            TEXT DEFAULT NULL,
    `proof_file`       VARCHAR(500) DEFAULT NULL,
    `added_by`         VARCHAR(100) DEFAULT NULL,
    `created_at`       DATETIME DEFAULT CURRENT_TIMESTAMP,
    `updated_at`       DATETIME DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_project_id` (`project_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

$res4 = $con->query("SHOW COLUMNS FROM `crm_project_expenses` LIKE 'status'");
if ($res4 && $res4->num_rows == 0) {
    $con->query("ALTER TABLE `crm_project_expenses` ADD COLUMN `status` VARCHAR(50) DEFAULT 'Approved'");
}
$res5 = $con->query("SHOW COLUMNS FROM `crm_project_expenses` LIKE 'manager_reason'");
if ($res5 && $res5->num_rows == 0) {
    $con->query("ALTER TABLE `crm_project_expenses` ADD COLUMN `manager_reason` TEXT DEFAULT NULL");
}

// =========================================================================
// AJAX ENDPOINTS
// =========================================================================
if (isset($_GET['ajax'])) {
    header('Content-Type: application/json');

    if ($_GET['ajax'] === 'get_stages_budget') {
        $pid = intval($_POST['project_id']);
        $r = $con->query("SELECT id, stage_name, allocated_budget, customer_billing_amount FROM crm_construction_stages WHERE project_id=$pid ORDER BY stage_order ASC");
        $stages = [];
        while ($row = $r->fetch_assoc()) $stages[] = $row;
        echo json_encode($stages);
        exit;
    }

    if ($_GET['ajax'] === 'save_stage_budgets') {
        $pid = intval($_POST['project_id']);
        $budgets = $_POST['budgets'] ?? []; // Array of {id, allocated, billing}
        if ($pid > 0 && is_array($budgets)) {
            $stmt = $con->prepare("UPDATE crm_construction_stages SET allocated_budget=?, customer_billing_amount=? WHERE id=? AND project_id=?");
            foreach ($budgets as $b) {
                $id = intval($b['id']);
                $allocated = floatval($b['allocated']);
                $billing = floatval($b['billing']);
                $stmt->bind_param("ddii", $allocated, $billing, $id, $pid);
                $stmt->execute();
            }
            $stmt->close();
            echo json_encode(['success'=>true]);
        } else {
            echo json_encode(['success'=>false, 'msg'=>'Invalid data']);
        }
        exit;
    }

    if ($_GET['ajax'] === 'get_expense_categories') {
        $r = $con->query("SELECT id, category_name FROM crm_expense_categories ORDER BY id ASC");
        $cats = [];
        while($row = $r->fetch_assoc()) $cats[] = $row;
        echo json_encode($cats);
        exit;
    }

    if ($_GET['ajax'] === 'add_expense_category') {
        $cat = mysqli_real_escape_string($con, trim($_POST['category_name']));
        if($cat != '') $con->query("INSERT INTO crm_expense_categories (category_name) VALUES ('$cat')");
        echo json_encode(['success'=>true]);
        exit;
    }

    if ($_GET['ajax'] === 'get_tasks') {
        $sid = intval($_POST['stage_id']);
        $r = $con->query("SELECT id, task_name FROM crm_construction_tasks WHERE stage_id=$sid ORDER BY task_name ASC");
        $tasks = [];
        while($row = $r->fetch_assoc()) $tasks[] = $row;
        echo json_encode($tasks);
        exit;
    }

    // --- DASHBOARD DATA ---
    if ($_GET['ajax'] === 'get_dashboard_data') {
        $pid = intval($_POST['project_id']);
        
        $r1 = $con->query("SELECT SUM(allocated_budget) as total_budget, SUM(customer_billing_amount) as total_billing FROM crm_construction_stages WHERE project_id=$pid");
        $stg_totals = $r1->fetch_assoc();
        $total_budget = round(floatval($stg_totals['total_budget']), 2);
        
        // Strictly enforce bottom-up calculation from stages
        $total_billing = round(floatval($stg_totals['total_billing']), 2);
        
        $expected_profit = round($total_billing - $total_budget, 2);
        
        $r2 = $con->query("SELECT SUM(amount) as total_spent FROM crm_project_expenses WHERE project_id=$pid AND status != 'Declined'");
        $total_spent = round(floatval($r2->fetch_assoc()['total_spent']), 2);
        
        $r3 = $con->query("SELECT SUM(amount) as total_received FROM crm_project_payments WHERE project_id=$pid");
        $total_received = floatval($r3->fetch_assoc()['total_received']);
        
        $pending_collections = $total_billing - $total_received;
        
        $stages_data = [];
        $r4 = $con->query("SELECT s.id, s.stage_name, s.allocated_budget, s.customer_billing_amount, (SELECT SUM(amount) FROM crm_project_expenses WHERE stage_id = s.id AND project_id=$pid AND status != 'Declined') as spent FROM crm_construction_stages s WHERE s.project_id=$pid ORDER BY s.stage_order ASC");
        while($row = $r4->fetch_assoc()) {
            $row['spent'] = floatval($row['spent']);
            $stages_data[] = $row;
        }
        
        $r5 = $con->query("SELECT SUM(amount) as spent FROM crm_project_expenses WHERE (stage_id IS NULL OR stage_id=0) AND project_id=$pid AND status != 'Declined'");
        $gen_spent = floatval($r5->fetch_assoc()['spent']);
        if ($gen_spent > 0) {
            $stages_data[] = [
                'stage_name' => 'General / Out of Scope Expenses',
                'allocated_budget' => 0,
                'customer_billing_amount' => 0,
                'spent' => $gen_spent
            ];
        }
        
        $cat_data = [];
        $r6 = $con->query("SELECT expense_category, SUM(amount) as total FROM crm_project_expenses WHERE project_id=$pid AND status != 'Declined' GROUP BY expense_category");
        while($row = $r6->fetch_assoc()) {
            $cat_data[] = [
                'category' => $row['expense_category'],
                'total' => floatval($row['total'])
            ];
        }
        
        $all_expenses = [];
        $r7 = $con->query("SELECT e.*, s.stage_name, t.task_name FROM crm_project_expenses e LEFT JOIN crm_construction_stages s ON e.stage_id=s.id LEFT JOIN crm_construction_tasks t ON e.task_id=t.id WHERE e.project_id=$pid AND e.status != 'Declined' ORDER BY s.stage_order ASC, e.expense_category ASC, e.expense_date DESC");
        while($row = $r7->fetch_assoc()) {
            $all_expenses[] = $row;
        }
        
        echo json_encode([
            'total_budget' => $total_budget,
            'total_billing' => $total_billing,
            'expected_profit' => $expected_profit,
            'total_spent' => $total_spent,
            'total_received' => $total_received,
            'pending_collections' => $pending_collections,
            'stages' => $stages_data,
            'categories' => $cat_data,
            'all_expenses' => $all_expenses
        ]);
        exit;
    }
    
    if ($_GET['ajax'] === 'set_contract_value') {
        $pid = intval($_POST['project_id']);
        $val = floatval($_POST['contract_value']);
        $stmt = $con->prepare("UPDATE crm_projects SET contract_value=? WHERE id=?");
        $stmt->bind_param("di", $val, $pid);
        $stmt->execute();
        echo json_encode(['success'=>true]);
        exit;
    }
    
    if ($_GET['ajax'] === 'get_stage_expenses') {
        $sid = intval($_POST['stage_id']);
        $pid = intval($_POST['project_id']);
        if ($sid == 0) {
            $q = "SELECT expense_category, SUM(amount) as total FROM crm_project_expenses WHERE project_id=$pid AND (stage_id IS NULL OR stage_id=0) AND status != 'Declined' GROUP BY expense_category";
        } else {
            $q = "SELECT expense_category, SUM(amount) as total FROM crm_project_expenses WHERE stage_id=$sid AND status != 'Declined' GROUP BY expense_category";
        }
        $r = $con->query($q);
        $data = [];
        while($row = $r->fetch_assoc()) $data[] = $row;
        echo json_encode($data);
        exit;
    }

    if ($_GET['ajax'] === 'import_expenses') {
        $pid = intval($_POST['project_id']);
        if ($pid > 0 && isset($_FILES['csv_file']) && $_FILES['csv_file']['error'] == 0) {
            $file = fopen($_FILES['csv_file']['tmp_name'], 'r');
            $header = fgetcsv($file); // skip header
            $count = 0;
            $stmt = $con->prepare("INSERT INTO crm_project_expenses (project_id, stage_id, task_id, expense_category, description, amount, expense_date) VALUES (?, ?, ?, ?, ?, ?, ?)");
            while (($data = fgetcsv($file)) !== FALSE) {
                if (count($data) >= 7) {
                    $date = $data[0];
                    $sid = intval($data[1]);
                    $tid = intval($data[2]);
                    $cat = trim($data[3]);
                    $desc = trim($data[4]);
                    $amt = floatval($data[5]);
                    
                    if($cat && $amt > 0) {
                        $sid = $sid > 0 ? $sid : NULL;
                        $tid = $tid > 0 ? $tid : NULL;
                        $stmt->bind_param("iiissds", $pid, $sid, $tid, $cat, $desc, $amt, $date);
                        $stmt->execute();
                        $count++;
                    }
                }
            }
            fclose($file);
            echo json_encode(['success'=>true, 'msg'=>"Imported $count expenses successfully."]);
        } else {
            echo json_encode(['success'=>false, 'msg'=>'Invalid file or project']);
        }
        exit;
    }

    // --- EXPENSES ---
    if ($_GET['ajax'] === 'get_expenses') {
        $pid = intval($_POST['project_id']);
        $r = $con->query("SELECT e.*, s.stage_name, t.task_name FROM crm_project_expenses e LEFT JOIN crm_construction_stages s ON e.stage_id=s.id LEFT JOIN crm_construction_tasks t ON e.task_id=t.id WHERE e.project_id=$pid ORDER BY e.expense_date DESC, e.id DESC");
        $expenses = [];
        while($row = $r->fetch_assoc()) $expenses[] = $row;
        echo json_encode($expenses);
        exit;
    }

    if ($_GET['ajax'] === 'save_expense') {
        $pid = intval($_POST['project_id']);
        $sid = intval($_POST['stage_id'] ?? 0);
        $sid_val = $sid > 0 ? $sid : 'NULL';
        $tid = intval($_POST['task_id'] ?? 0);
        $tid_val = $tid > 0 ? $tid : 'NULL';
        $cat = mysqli_real_escape_string($con, $_POST['expense_category']);
        $date = mysqli_real_escape_string($con, $_POST['expense_date']);
        $amt = floatval($_POST['amount']);
        $desc = mysqli_real_escape_string($con, $_POST['description'] ?? '');
        $edit_id = intval($_POST['edit_id'] ?? 0);

        // Multiple file upload
        $removed_proofs = isset($_POST['removed_existing_proofs']) ? $_POST['removed_existing_proofs'] : [];
        $existing_proofs = [];
        if ($edit_id > 0) {
            $curr = $con->query("SELECT proof_file FROM crm_project_expenses WHERE id=$edit_id")->fetch_assoc();
            if ($curr && !empty($curr['proof_file'])) {
                $existing_proofs = explode(',', $curr['proof_file']);
            }
        }
        
        $kept_proofs = [];
        foreach ($existing_proofs as $ep) {
            if (!in_array($ep, $removed_proofs)) {
                $kept_proofs[] = $ep;
            }
        }

        $uploaded_paths = [];
        $has_upload = false;
        if (isset($_FILES['proof_file']['name'])) {
            foreach ($_FILES['proof_file']['name'] as $n) {
                if (!empty($n)) { $has_upload = true; break; }
            }
        }
        if ($has_upload) {
            $dir = __DIR__ . '/uploads/financials/';
            if (!is_dir($dir)) mkdir($dir, 0777, true);
            foreach ($_FILES['proof_file']['name'] as $key => $name) {
                if ($name) {
                    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
                    if (in_array($ext, ['jpg','jpeg','png','pdf','webp','gif'])) {
                        $safe = 'exp_' . time() . rand(100,999) . '_' . $key . '.' . $ext;
                        if (move_uploaded_file($_FILES['proof_file']['tmp_name'][$key], $dir . $safe)) {
                            $uploaded_paths[] = 'uploads/financials/' . $safe;
                        }
                    }
                }
            }
        }

        $all_proofs = array_merge($kept_proofs, $uploaded_paths);
        $proof_sql = "";
        if ($edit_id > 0) {
            $paths_str = implode(',', $all_proofs);
            $proof_sql = ", proof_file='$paths_str'";
        } else if (count($uploaded_paths) > 0) {
            $paths_str = implode(',', $uploaded_paths);
            $proof_sql = ", proof_file='$paths_str'";
        }

        if ($edit_id > 0) {
            $con->query("UPDATE crm_project_expenses SET stage_id=$sid_val, task_id=$tid_val, expense_category='$cat', expense_date='$date', amount=$amt, description='$desc' $proof_sql WHERE id=$edit_id AND project_id=$pid");
        } else {
            $con->query("INSERT INTO crm_project_expenses (project_id, stage_id, task_id, expense_category, expense_date, amount, description, added_by) VALUES ($pid, $sid_val, $tid_val, '$cat', '$date', $amt, '$desc', '$userName')");
            if ($proof_sql) {
                $new_id = $con->insert_id;
                $con->query("UPDATE crm_project_expenses SET " . ltrim($proof_sql, ", ") . " WHERE id=$new_id");
            }
        }
        echo json_encode(['success'=>true]);
        exit;
    }

    if ($_GET['ajax'] === 'review_expense') {
        if (!$is_admin_user) { echo json_encode(['success'=>false, 'msg'=>'Admin only']); exit; }
        $id = intval($_POST['id']);
        $status = mysqli_real_escape_string($con, $_POST['status']);
        $reason = mysqli_real_escape_string($con, $_POST['reason'] ?? '');
        $con->query("UPDATE crm_project_expenses SET status='$status', manager_reason='$reason' WHERE id=$id");
        echo json_encode(['success'=>true]);
        exit;
    }

    if ($_GET['ajax'] === 'delete_expense') {
        $id = intval($_POST['id']);
        $con->query("DELETE FROM crm_project_expenses WHERE id=$id");
        echo json_encode(['success'=>true]);
        exit;
    }

    // --- PAYMENTS ---
    if ($_GET['ajax'] === 'get_payments') {
        $pid = intval($_POST['project_id']);
        $r = $con->query("SELECT p.*, s.stage_name FROM crm_project_payments p LEFT JOIN crm_construction_stages s ON p.stage_id=s.id WHERE p.project_id=$pid ORDER BY p.payment_date DESC, p.id DESC");
        $payments = [];
        while($row = $r->fetch_assoc()) $payments[] = $row;
        echo json_encode($payments);
        exit;
    }

    if ($_GET['ajax'] === 'save_payment') {
        $pid = intval($_POST['project_id']);
        $sid = intval($_POST['stage_id'] ?? 0);
        $sid_val = $sid > 0 ? $sid : 'NULL';
        $type = mysqli_real_escape_string($con, $_POST['payment_type']);
        $date = mysqli_real_escape_string($con, $_POST['payment_date']);
        $amt = floatval($_POST['amount']);
        $mode = mysqli_real_escape_string($con, $_POST['payment_mode']);
        $ref = mysqli_real_escape_string($con, $_POST['reference_no'] ?? '');
        $notes = mysqli_real_escape_string($con, $_POST['notes'] ?? '');
        $edit_id = intval($_POST['edit_id'] ?? 0);

        // Multiple file upload
        $proof_sql = "";
        $uploaded_paths = [];
        if (!empty($_FILES['proof_file']['name'][0])) {
            $dir = __DIR__ . '/uploads/financials/';
            if (!is_dir($dir)) mkdir($dir, 0777, true);
            foreach ($_FILES['proof_file']['name'] as $key => $name) {
                if ($name) {
                    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
                    if (in_array($ext, ['jpg','jpeg','png','pdf'])) {
                        $safe = 'pay_' . time() . rand(100,999) . '_' . $key . '.' . $ext;
                        if (move_uploaded_file($_FILES['proof_file']['tmp_name'][$key], $dir . $safe)) {
                            $uploaded_paths[] = 'uploads/financials/' . $safe;
                        }
                    }
                }
            }
            if(count($uploaded_paths) > 0) {
                $paths_str = implode(',', $uploaded_paths);
                $proof_sql = ", proof_file='$paths_str'";
            }
        }

        if ($edit_id > 0) {
            $con->query("UPDATE crm_project_payments SET stage_id=$sid_val, payment_type='$type', payment_date='$date', amount=$amt, payment_mode='$mode', reference_no='$ref', notes='$notes' $proof_sql WHERE id=$edit_id AND project_id=$pid");
        } else {
            $con->query("INSERT INTO crm_project_payments (project_id, stage_id, payment_type, payment_date, amount, payment_mode, reference_no, notes, added_by) VALUES ($pid, $sid_val, '$type', '$date', $amt, '$mode', '$ref', '$notes', '$userName')");
            if ($proof_sql) {
                $new_id = $con->insert_id;
                $con->query("UPDATE crm_project_payments SET " . ltrim($proof_sql, ", ") . " WHERE id=$new_id");
            }
        }
        echo json_encode(['success'=>true]);
        exit;
    }

    if ($_GET['ajax'] === 'delete_payment') {
        $id = intval($_POST['id']);
        $con->query("DELETE FROM crm_project_payments WHERE id=$id");
        echo json_encode(['success'=>true]);
        exit;
    }
    
    // Add get_dashboard etc. later
    
    echo json_encode(['success'=>false, 'msg'=>'Unknown endpoint']);
    exit;
}

// Fetch active projects for dropdown
$projects = $con->query("SELECT id, project_number, customer_name, service_type FROM crm_projects WHERE status='Active' ORDER BY customer_name ASC");

$preselect = isset($_GET['project_id']) ? intval($_GET['project_id']) : 0;
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Project Financials - CRM</title>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.bundle.min.js"></script>

<style>
/* Base Styles Replicating db-project-tasks.php */
body { font-family: 'Poppins', sans-serif; background-color: #f1f5f9; color: #1e293b; margin:0; padding-bottom: 50px; }
.container-fluid { padding: 20px; max-width: 1400px; margin: 0 auto; }

/* Page Header */
.page-header {
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
    color: white; padding: 24px 30px; border-radius: 16px; margin-bottom: 24px;
    display: flex; justify-content: space-between; align-items: center;
    box-shadow: 0 10px 25px rgba(30,58,138,0.15); position: relative; overflow: hidden;
}
.page-header::before {
    content:''; position:absolute; top:0; left:0; width:100%; height:100%;
    background: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" opacity="0.05"><circle cx="50" cy="50" r="40" fill="white"/></svg>') repeat;
    z-index: 1; pointer-events: none;
}
.page-header h1 { font-size: 1.8rem; font-weight: 700; margin: 0; position: relative; z-index: 2; display:flex; align-items:center; gap:10px; }
.header-sub { font-size: 14px; color: #cbd5e1; margin-top: 6px; position: relative; z-index: 2; }
.btn-back { background: rgba(255,255,255,0.15); color: white; border: none; padding: 10px 20px; border-radius: 10px; font-weight: 600; text-decoration: none; transition: all 0.3s; display:flex; align-items:center; gap:8px; }
.btn-back:hover { background: rgba(255,255,255,0.25); color: white; text-decoration: none; }

/* Top Bar Project Selector */
.top-bar {
    background: white; padding: 16px 24px; border-radius: 14px; margin-bottom: 24px;
    box-shadow: 0 4px 15px rgba(0,0,0,0.03); display: flex; align-items: center; gap: 20px;
}
.form-control { border-radius: 10px; border: 1px solid #cbd5e1; padding: 10px 14px; font-size: 14px; height: auto; box-shadow: none; transition: border-color 0.2s; }
.form-control:focus { border-color: #3b82f6; box-shadow: 0 0 0 3px rgba(59,130,246,0.1); }

/* Tabs Navigation */
.nav-pills .nav-link { font-weight:600; color:#475569; padding:8px 16px; border-radius:8px; margin-right:5px; transition:all 0.3s; background:white; border:1px solid #e2e8f0; }
.nav-pills .nav-link:hover { background:#f1f5f9; color:#1e3a8a; }
.nav-pills .nav-link.active { background:linear-gradient(135deg,#1e3a8a,#1e40af); color:white; border-color:transparent; box-shadow:0 4px 10px rgba(30,58,138,0.2); }

/* Panels */
.tab-content > .tab-pane { display: none; }
.tab-content > .active { display: block; }

.card-panel {
    background: white; border-radius: 16px; padding: 24px;
    box-shadow: 0 4px 20px rgba(0,0,0,0.03); margin-bottom: 24px;
}
.section-title { font-size: 1.1rem; font-weight: 700; color: #1e293b; margin-bottom: 16px; display:flex; align-items:center; gap:8px; }
.btn-primary-custom { background: linear-gradient(135deg,#1e3a8a,#1e40af); color: white; border: none; padding: 10px 24px; border-radius: 9px; font-weight: 600; transition: all 0.2s; }
.btn-primary-custom:hover { transform: translateY(-1px); box-shadow: 0 6px 15px rgba(30,58,138,0.2); color:white; }

.table th { border-top: none; background: #f8fafc; color: #475569; font-weight: 600; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px; }
.table td { vertical-align: middle; color: #334155; border-bottom: 1px solid #f1f5f9; }
</style>
</head>
<body>
<div class="container-fluid">

    <div class="page-header">
        <div>
            <h1><i class="fas fa-wallet"></i> Project Financials</h1>
            <div class="header-sub">Manage budgets, log expenses, and track customer payments per stage</div>
        </div>
        <div style="display:flex;gap:10px;">
            <a href="db-dashboard.php" class="btn-back" style="background:linear-gradient(135deg,#0a1628 0%,#1a3a72 100%); color:white; border:none;"><i class="fas fa-home"></i> Home</a>
        </div>
    </div>

    <!-- TOP CONTROL BAR -->
    <div class="top-bar" style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:15px; padding-bottom:0; background:transparent; border:none; box-shadow:none;">
        
        <!-- TABS (MOVED UP) -->
        <div id="main_nav_tabs" style="display:none; width: 100%; overflow-x: auto;">
            <div style="display:flex; justify-content:space-between; align-items:center; width:100%; flex-wrap:wrap; gap:15px;">
                <ul class="nav nav-pills" id="finTabs" role="tablist" style="margin:0; padding:5px; flex-wrap:nowrap; white-space:nowrap;">
                    <?php if($can_view_dash): ?>
                    <li class="nav-item"><a class="nav-link active" id="dash-tab" data-toggle="tab" href="#tab-dash" role="tab"><i class="fas fa-chart-pie mr-2"></i>Dashboard</a></li>
                    <?php endif; ?>
                    <?php if($can_view_budgets): ?>
                    <li class="nav-item"><a class="nav-link <?php echo !$can_view_dash ? 'active' : ''; ?>" id="budgets-tab" data-toggle="tab" href="#tab-budgets" role="tab"><i class="fas fa-coins mr-2"></i>Stage Budgets</a></li>
                    <?php endif; ?>
                    <?php if($can_view_expenses): ?>
                    <li class="nav-item"><a class="nav-link <?php echo (!$can_view_dash && !$can_view_budgets) ? 'active' : ''; ?>" id="expenses-tab" data-toggle="tab" href="#tab-expenses" role="tab"><i class="fas fa-file-invoice-dollar mr-2"></i>Expenses</a></li>
                    <?php endif; ?>
                    <?php if($can_view_payments): ?>
                    <li class="nav-item"><a class="nav-link <?php echo (!$can_view_dash && !$can_view_budgets && !$can_view_expenses) ? 'active' : ''; ?>" id="payments-tab" data-toggle="tab" href="#tab-payments" role="tab"><i class="fas fa-hand-holding-usd mr-2"></i>Customer Payments</a></li>
                    <?php endif; ?>
                    <?php if($can_view_reports): ?>
                    <li class="nav-item"><a class="nav-link" style="background:#10b981; color:white; margin-left:10px; border-color:transparent;" href="db-reports-page.php"><i class="fas fa-file-export mr-2"></i>System Reports</a></li>
                    <?php endif; ?>
                </ul>

                <!-- PROJECT SELECTOR (RIGHT SIDE) -->
                <div style="display:flex; align-items:center; background:white; padding:8px 15px; border-radius:12px; box-shadow:0 2px 10px rgba(0,0,0,0.05);">
                    <label style="color:#475569;font-weight:600;margin:0 10px 0 0;white-space:nowrap;"><i class="fas fa-folder-open" style="margin-right:6px;color:#1e3a8a;"></i>Select Project:</label>
                    <select class="form-control form-control-sm" id="sel_project" style="min-width:300px; height:auto; padding:6px 12px; font-weight:600;" onchange="onProjectChange()">
                        <option value="">— Choose Active Project —</option>
                        <?php while ($p = $projects->fetch_assoc()): ?>
                        <option value="<?php echo $p['id']; ?>" <?php echo $preselect==$p['id']?'selected':''; ?>>
                            <?php echo htmlspecialchars($p['project_number'].' — '.$p['customer_name'].' ('.$p['service_type'].')'); ?>
                        </option>
                        <?php endwhile; ?>
                    </select>
                </div>
            </div>
        </div>
    </div>

    <!-- INITIAL PROJECT SELECTOR (IF NONE SELECTED) -->
    <div id="initial_project_selector" style="text-align:center; padding: 40px; background:white; border-radius:16px; box-shadow:0 4px 20px rgba(0,0,0,0.03);">
        <h4 style="color:#1e3a8a; margin-bottom:20px;">Please Select a Project to Manage Financials</h4>
        <select class="form-control mx-auto" id="sel_project_initial" style="max-width:400px; height:auto; padding:10px 14px; font-size:16px; font-weight:600;" onchange="$('#sel_project').val(this.value); onProjectChange();">
            <option value="">— Choose Active Project —</option>
            <?php 
            // Reset pointer to reuse options
            $projects->data_seek(0);
            while ($p = $projects->fetch_assoc()): ?>
            <option value="<?php echo $p['id']; ?>" <?php echo $preselect==$p['id']?'selected':''; ?>>
                <?php echo htmlspecialchars($p['project_number'].' — '.$p['customer_name'].' ('.$p['service_type'].')'); ?>
            </option>
            <?php endwhile; ?>
        </select>
    </div>

    <div id="main_area" style="display:none; margin-top:15px;">

        <div class="tab-content">
            
            <?php if($can_view_dash): ?>
            <!-- DASHBOARD TAB -->
            <div class="tab-pane fade show active" id="tab-dash" role="tabpanel">
                <div id="dashboard_content">
                    <div class="card-panel" style="text-align:center; padding: 60px;">
                        <i class="fas fa-spinner fa-spin" style="font-size:3rem; color:#cbd5e1; margin-bottom:15px;"></i>
                        <h4 style="color:#475569;">Loading Dashboard...</h4>
                    </div>
                </div>
            </div>
            <?php endif; ?>

            <?php if($can_view_budgets): ?>
            <!-- STAGE BUDGETS TAB -->
            <div class="tab-pane fade <?php echo !$can_view_dash ? 'show active' : ''; ?>" id="tab-budgets" role="tabpanel">
                <div class="card-panel">
                    <div class="section-title"><i class="fas fa-sliders-h"></i> Allocate Budgets per Stage</div>
                    <p style="color:#64748b; font-size:14px; margin-bottom:20px;">Define the Fixed Cost (What you plan to spend) and the Customer Billing Amount (What the customer pays) for each stage.</p>
                    
                    <div class="table-responsive">
                        <table class="table" id="table_budgets">
                            <thead>
                                <tr>
                                    <th>Stage Name</th>
                                    <th style="width:250px;">Allocated Budget (Estimated Cost)</th>
                                    <th style="width:250px;">Customer Billing Amount</th>
                                </tr>
                            </thead>
                            <tbody id="budgets_tbody">
                                <!-- Loaded via JS -->
                            </tbody>
                        </table>
                    </div>
                    <div style="text-align:right; margin-top:20px;">
                        <button class="btn-primary-custom" onclick="saveStageBudgets()"><i class="fas fa-save mr-2"></i>Save Budgets</button>
                    </div>
                </div>
            </div>
            <?php endif; ?>

            <?php if($can_view_expenses): ?>
            <!-- EXPENSES TAB -->
            <div class="tab-pane fade <?php echo (!$can_view_dash && !$can_view_budgets) ? 'show active' : ''; ?>" id="tab-expenses" role="tabpanel">
                <div class="card-panel">
                    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;">
                        <div class="section-title" style="margin:0;"><i class="fas fa-file-invoice-dollar"></i> Expense Log</div>
                        <div>
                            <?php if($can_upload_expenses): ?>
                            <button class="btn btn-sm btn-outline-secondary mr-1" onclick="printSelectedVouchers()" id="btn_print_selected" style="display:none;"><i class="fas fa-print"></i> Print Vouchers</button>
                            <button class="btn btn-sm btn-outline-info mr-1" onclick="exportAllExpensesCSV()"><i class="fas fa-download"></i> Export CSV</button>
                            <button class="btn btn-sm btn-outline-success mr-1" onclick="$('#importExpModal').modal('show')"><i class="fas fa-file-excel"></i> Import</button>
                            <button class="btn btn-sm btn-primary-custom" onclick="openExpenseModal()"><i class="fas fa-plus"></i> Add Expense</button>
                            <?php endif; ?>
                        </div>
                    </div>
                    
                    <!-- FILTER ROW -->
                    <div style="display:flex; gap:10px; margin-bottom:15px; align-items:center; flex-wrap:wrap; background:#f8fafc; padding:10px; border-radius:8px; border:1px solid #e2e8f0;">
                        <div style="font-weight:600; color:#475569; margin-right:5px;"><i class="fas fa-filter"></i> Filter:</div>
                        <input type="date" id="filter_exp_from" class="form-control form-control-sm" style="width:130px;" placeholder="From Date" onchange="applyExpenseFilter()">
                        <input type="date" id="filter_exp_to" class="form-control form-control-sm" style="width:130px;" placeholder="To Date" onchange="applyExpenseFilter()">
                        <select id="filter_exp_cat" class="form-control form-control-sm" style="width:160px;" onchange="applyExpenseFilter()">
                            <option value="">All Categories</option>
                        </select>
                        <select id="filter_exp_stage" class="form-control form-control-sm" style="width:160px;" onchange="applyExpenseFilter()">
                            <option value="">All Stages</option>
                        </select>
                        <button class="btn btn-sm btn-light border" onclick="resetExpenseFilter()" title="Reset Filters"><i class="fas fa-redo"></i></button>
                    </div>

                    <div class="table-responsive">
                        <table class="table" id="table_expenses">
                            <thead>
                                <tr>
                                    <th style="width:30px;"><input type="checkbox" id="chk_all_expenses" onclick="toggleAllExpenses(this)"></th>
                                    <th>Date</th>
                                    <th>Stage & Task</th>
                                    <th>Category</th>
                                    <th>Description</th>
                                    <th>Amount (₹)</th>
                                    <th>Proof(s)</th>
                                    <th>Status</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody id="expenses_tbody"></tbody>
                        </table>
                    </div>
                </div>
            </div>
            <?php endif; ?>

            <?php if($can_view_payments): ?>
            <!-- PAYMENTS TAB -->
            <div class="tab-pane fade <?php echo (!$can_view_dash && !$can_view_budgets && !$can_view_expenses) ? 'show active' : ''; ?>" id="tab-payments" role="tabpanel">
                <div class="card-panel">
                    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;">
                        <div class="section-title" style="margin:0;"><i class="fas fa-hand-holding-usd"></i> Customer Payments</div>
                        <?php if($can_add_payments): ?>
                        <button class="btn btn-sm btn-primary-custom" onclick="openPaymentModal()"><i class="fas fa-plus"></i> Add Payment</button>
                        <?php endif; ?>
                    </div>

                    <!-- FILTER ROW -->
                    <div style="display:flex; gap:10px; margin-bottom:15px; align-items:center; flex-wrap:wrap; background:#f8fafc; padding:10px; border-radius:8px; border:1px solid #e2e8f0;">
                        <div style="font-weight:600; color:#475569; margin-right:5px;"><i class="fas fa-filter"></i> Filter:</div>
                        <input type="date" id="filter_pay_from" class="form-control form-control-sm" style="width:130px;" placeholder="From Date" onchange="applyPaymentFilter()">
                        <input type="date" id="filter_pay_to" class="form-control form-control-sm" style="width:130px;" placeholder="To Date" onchange="applyPaymentFilter()">
                        <select id="filter_pay_stage" class="form-control form-control-sm" style="width:160px;" onchange="applyPaymentFilter()">
                            <option value="">All Stages</option>
                        </select>
                        <button class="btn btn-sm btn-light border" onclick="resetPaymentFilter()" title="Reset Filters"><i class="fas fa-redo"></i></button>
                    </div>

                    <div class="table-responsive">
                        <table class="table" id="table_payments">
                            <thead>
                                <tr>
                                    <th>Date</th>
                                    <th>Type & Stage</th>
                                    <th>Mode</th>
                                    <th>Ref No / Notes</th>
                                    <th>Amount (₹)</th>
                                    <th>Proof(s)</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody id="payments_tbody"></tbody>
                        </table>
                    </div>
                </div>
            </div>
            <?php endif; ?>

        </div>

    </div>

    <div id="no_project_msg" style="text-align:center;padding:80px;color:#64748b;">
        <i class="fas fa-wallet" style="font-size:3.5rem;color:#cbd5e1;display:block;margin-bottom:16px;"></i>
        <h3 style="font-size:1.5rem; font-weight:600; color:#475569;">Select a Project</h3>
        <p>Please select an active project from the dropdown above to view its financials.</p>
    </div>

    <!-- CONTRACT VALUE MODAL -->
    <div class="modal fade" id="contractModal" data-backdrop="static">
        <div class="modal-dialog modal-dialog-centered">
            <form id="contractForm" onsubmit="saveContractValue(event)">
                <input type="hidden" name="project_id" id="contract_project_id">
                <div class="modal-content" style="border:none; border-radius:16px; box-shadow:0 10px 30px rgba(0,0,0,0.1);">
                    <div class="modal-header" style="background:#f8fafc; border-bottom:1px solid #e2e8f0; border-radius:16px 16px 0 0; padding:15px 25px;">
                        <h5 class="modal-title" style="color:#1e3a8a; font-weight:800;"><i class="fas fa-file-contract mr-2"></i> Set Overall Budget (Contract Value)</h5>
                        <button type="button" class="close" data-dismiss="modal">&times;</button>
                    </div>
                    <div class="modal-body" style="padding:25px;">
                        <p class="text-muted" style="font-size:14px; margin-bottom:15px;">Enter the overall agreed budget you need to collect from the customer. Setting this overrides the sum of individual stage budgets.</p>
                        <div class="form-group">
                            <label style="font-weight:600; color:#475569;">Total Contract Value (₹)</label>
                            <input type="number" class="form-control" id="contract_val_input" name="contract_value" step="0.01" required>
                        </div>
                    </div>
                    <div class="modal-footer" style="border-top:1px solid #e2e8f0; padding:15px 25px;">
                        <button type="button" class="btn btn-light border" data-dismiss="modal" style="font-weight:600;">Cancel</button>
                        <button type="submit" class="btn btn-primary-custom" id="btn_save_contract"><i class="fas fa-save mr-1"></i> Save Budget</button>
                    </div>
                </div>
            </form>
        </div>
    </div>

</div> <!-- end container -->

<!-- EXPENSE MODAL -->
<div class="modal fade" id="expenseModal">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <form id="expenseForm" onsubmit="saveExpense(event)">
                <div class="modal-header" style="background: linear-gradient(135deg,#1e3a8a,#1e40af); border-radius: .3rem .3rem 0 0;">
                    <h5 class="modal-title" style="color:white; font-weight:600;"><i class="fas fa-file-invoice-dollar"></i> <span id="exp_modal_title">Add Expense</span></h5>
                    <button type="button" class="close" data-dismiss="modal" style="color:white; text-shadow:none; opacity:0.8;">&times;</button>
                </div>
                <div class="modal-body" style="background:#f8fafc;">
                    <input type="hidden" id="exp_edit_id" name="edit_id" value="0">
                    <input type="hidden" id="exp_project_id" name="project_id" value="">
                    
                    <div class="form-group mb-4" style="background:#ffffff; padding:15px; border-radius:8px; border:1px solid #e2e8f0; box-shadow:0 1px 3px rgba(0,0,0,0.05);">
                        <label style="margin-bottom:10px; display:block; color:#1e3a8a; font-weight:600;">Expense Scope</label>
                        <div class="custom-control custom-radio custom-control-inline">
                            <input type="radio" id="type_stage" name="expense_scope" class="custom-control-input" value="stage" checked onchange="toggleExpenseScope()">
                            <label class="custom-control-label" for="type_stage">Stage-wise Expense</label>
                        </div>
                        <div class="custom-control custom-radio custom-control-inline">
                            <input type="radio" id="type_general" name="expense_scope" class="custom-control-input" value="general" onchange="toggleExpenseScope()">
                            <label class="custom-control-label" for="type_general">General / Other Expense</label>
                        </div>
                    </div>

                    <div class="row" id="row_stage_task">
                        <div class="col-md-6">
                            <div class="form-group">
                                <label style="font-weight:600; color:#475569;">Stage *</label>
                                <select class="form-control" id="exp_stage_id" name="stage_id" onchange="loadTasksForStage(this.value)"></select>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="form-group">
                                <label style="font-weight:600; color:#475569;">Task (Optional)</label>
                                <select class="form-control" id="exp_task_id" name="task_id">
                                    <option value="">- Select Stage First -</option>
                                </select>
                            </div>
                        </div>
                    </div>

                    <div class="row">
                        <div class="col-md-4">
                            <div class="form-group">
                                <label style="font-weight:600; color:#475569;">Category *</label>
                                <select class="form-control" id="exp_category" name="expense_category" required onchange="handleCategoryChange(this)">
                                    <option value="">- Select -</option>
                                </select>
                            </div>
                        </div>
                        <div class="col-md-4">
                            <div class="form-group">
                                <label style="font-weight:600; color:#475569;">Expense Date *</label>
                                <input type="date" class="form-control" id="exp_date" name="expense_date" required>
                            </div>
                        </div>
                        <div class="col-md-4">
                            <div class="form-group">
                                <label style="font-weight:600; color:#475569;">Amount (₹) *</label>
                                <input type="number" step="0.01" class="form-control" id="exp_amount" name="amount" required>
                            </div>
                        </div>
                    </div>

                    <div class="row mt-2">
                        <div class="col-md-6">
                            <div class="form-group">
                                <label style="font-weight:600; color:#475569;">Description (Notes)</label>
                                <textarea class="form-control" id="exp_description" name="description" rows="3" placeholder="e.g. 50 bags of ultra tech cement..."></textarea>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="form-group">
                                <label style="font-weight:600; color:#475569;" id="lbl_exp_proof">Upload Bill/Receipt *</label>
                                <div style="display:flex; gap:10px; align-items:center; margin-bottom:8px;">
                                    <button type="button" class="btn btn-sm" style="flex:1; background:#ecfdf5; color:#065f46; border:1px solid #10b981; font-weight:600;" onclick="$('#exp_proof_camera').click()"><i class="fas fa-camera mr-1"></i> Take Photo</button>
                                    <button type="button" class="btn btn-sm" style="flex:1; background:#f8fafc; color:#475569; border:1px solid #cbd5e1; font-weight:600;" onclick="$('#exp_proof_gallery').click()"><i class="fas fa-folder-open mr-1"></i> Choose File</button>
                                </div>
                                <div id="exp_proof_selected" style="display:none; flex-direction:column; gap:8px; margin-top:10px;">
                                    <div style="font-size:12px; color:#3b82f6; font-weight:600; display:flex; align-items:center; gap:8px;">
                                        <i class="fas fa-check-circle"></i> <span>Files selected</span>
                                        <button type="button" class="btn btn-sm text-danger p-0 m-0" onclick="clearExpenseProof()" style="font-size:12px;" title="Clear"><i class="fas fa-times"></i></button>
                                    </div>
                                    <div id="exp_proof_preview_container" style="display:flex; gap:10px; flex-wrap:wrap;"></div>
                                </div>
                                <input type="file" id="exp_proof_camera" name="proof_file[]" accept="image/*" capture="environment" style="display:none;" onchange="handleExpenseProofSelect(this)">
                                <input type="file" id="exp_proof_gallery" name="proof_file[]" multiple accept="image/*,application/pdf" style="display:none;" onchange="handleExpenseProofSelect(this)">
                                <div id="removed_existing_proofs_container"></div>
                                <small class="text-muted mt-1 d-block">Multiple files allowed. Mobile camera supported.</small>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="submit" class="btn btn-primary btn-primary-custom" id="btn_save_exp"><i class="fas fa-save"></i> Save</button>
                    <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- PAYMENT MODAL -->
<div class="modal fade" id="paymentModal">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <form id="paymentForm" onsubmit="savePayment(event)">
                <div class="modal-header" style="background: linear-gradient(135deg,#1e3a8a,#1e40af); border-radius: .3rem .3rem 0 0;">
                    <h5 class="modal-title" style="color:white; font-weight:600;"><i class="fas fa-hand-holding-usd"></i> <span id="pay_modal_title">Add Payment</span></h5>
                    <button type="button" class="close" data-dismiss="modal" style="color:white; text-shadow:none; opacity:0.8;">&times;</button>
                </div>
                <div class="modal-body">
                    <input type="hidden" id="pay_edit_id" name="edit_id" value="0">
                    <input type="hidden" id="pay_project_id" name="project_id" value="">
                    <div class="row">
                        <div class="col-md-6">
                            <div class="form-group">
                                <label>Payment Type *</label>
                                <select class="form-control" id="pay_type" name="payment_type" required onchange="togglePayStage()">
                                    <option>Advance Payment</option>
                                    <option selected>Stage Payment</option>
                                    <option>Final Settlement</option>
                                </select>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="form-group" id="div_pay_stage">
                                <label>For Stage</label>
                                <select class="form-control" id="pay_stage_id" name="stage_id"></select>
                            </div>
                        </div>
                    </div>
                    <div class="row">
                        <div class="col-md-6">
                            <div class="form-group">
                                <label>Payment Date *</label>
                                <input type="date" class="form-control" id="pay_date" name="payment_date" required>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="form-group">
                                <label>Amount Received (₹) *</label>
                                <input type="number" step="0.01" class="form-control" id="pay_amount" name="amount" required>
                            </div>
                        </div>
                    </div>
                    <div class="row">
                        <div class="col-md-6">
                            <div class="form-group">
                                <label>Payment Mode *</label>
                                <select class="form-control" id="pay_mode" name="payment_mode" required>
                                    <option>Bank Transfer (NEFT/RTGS)</option>
                                    <option>UPI / QR</option>
                                    <option>Cheque</option>
                                    <option>Cash</option>
                                </select>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="form-group">
                                <label>Reference No (Txn ID / Cheque No)</label>
                                <input type="text" class="form-control" id="pay_ref" name="reference_no">
                            </div>
                        </div>
                    </div>
                    <div class="form-group">
                        <label>Notes</label>
                        <textarea class="form-control" id="pay_notes" name="notes" rows="2"></textarea>
                    </div>
                    <div class="form-group">
                        <label id="lbl_pay_proof">Upload Receipt/Screenshot *</label>
                        <div style="display:flex; gap:10px; align-items:center; margin-bottom:8px;">
                            <button type="button" class="btn btn-sm" style="flex:1; background:#ecfdf5; color:#065f46; border:1px solid #10b981; font-weight:600;" onclick="$('#pay_proof_camera').click()"><i class="fas fa-camera mr-1"></i> Take Photo</button>
                            <button type="button" class="btn btn-sm" style="flex:1; background:#f8fafc; color:#475569; border:1px solid #cbd5e1; font-weight:600;" onclick="$('#pay_proof_gallery').click()"><i class="fas fa-folder-open mr-1"></i> Choose File</button>
                        </div>
                        <div id="pay_proof_selected" style="font-size:12px; color:#3b82f6; font-weight:600; display:none; align-items:center; gap:8px;">
                            <i class="fas fa-check-circle"></i> <span>Files selected</span>
                            <button type="button" class="btn btn-sm text-danger p-0 m-0" onclick="$('#pay_proof_camera').val(''); $('#pay_proof_gallery').val(''); $('#pay_proof_selected').hide(); $('#lbl_pay_proof').html('Upload Receipt/Screenshot *');" style="font-size:12px;" title="Clear"><i class="fas fa-times"></i></button>
                        </div>
                        <input type="file" id="pay_proof_camera" name="proof_file[]" accept="image/*" capture="environment" style="display:none;" onchange="$('#pay_proof_selected').css('display','flex'); $('#lbl_pay_proof').html('Proof <i class=\'fas fa-check text-success\'></i>');">
                        <input type="file" id="pay_proof_gallery" name="proof_file[]" multiple accept="image/*,application/pdf" style="display:none;" onchange="$('#pay_proof_selected').css('display','flex'); $('#lbl_pay_proof').html('Proof <i class=\'fas fa-check text-success\'></i>');">
                        <small class="text-muted mt-1 d-block">You can upload multiple files/photos. Camera supported on mobile.</small>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="submit" class="btn btn-primary btn-primary-custom" id="btn_save_pay"><i class="fas fa-save"></i> Save</button>
                    <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- IMPORT CSV MODAL -->
<div class="modal fade" id="importExpModal">
    <div class="modal-dialog">
        <div class="modal-content">
            <form id="importExpForm" onsubmit="importExpenses(event)">
                <div class="modal-header" style="background: linear-gradient(135deg,#10b981,#047857); border-radius: .3rem .3rem 0 0;">
                    <h5 class="modal-title" style="color:white; font-weight:600;"><i class="fas fa-file-excel"></i> Import Expenses (CSV)</h5>
                    <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
                </div>
                <div class="modal-body">
                    <p style="color:#475569;">You can bulk upload expenses using a CSV file. Please use the exact format provided in the template below.</p>
                    <div class="text-center mb-4 p-3" style="background:#f8fafc; border-radius:8px; border:1px dashed #cbd5e1;">
                        <a href="data:text/csv;charset=utf-8,Date,Stage_ID,Task_ID,Category,Description,Amount,Receipt_URL%0A2026-05-23,,,Materials,Sample Expense,150.00," download="expense_template.csv" class="btn btn-outline-success"><i class="fas fa-download mr-2"></i>Download CSV Template</a>
                        <small class="d-block mt-2 text-muted">Leave Stage_ID and Task_ID blank for General Expenses</small>
                    </div>
                    <div class="form-group">
                        <label style="font-weight:600; color:#1e3a8a;">Upload Filled CSV *</label>
                        <input type="file" name="csv_file" class="form-control-file p-2" style="border:1px solid #e2e8f0; border-radius:4px;" accept=".csv" required>
                        <input type="hidden" name="project_id" id="import_project_id">
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="submit" class="btn btn-success" id="btn_import_exp"><i class="fas fa-upload mr-1"></i> Upload & Import</button>
                    <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
                </div>
            </form>
        </div>
    </div>
</div>

</div>

<!-- CALCULATION MODAL -->
<div class="modal fade" id="pnlModal">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header" style="background:#1e3a8a; color:white;">
                <h5 class="modal-title" id="calc_modal_title"><i class="fas fa-calculator"></i> Calculation Report</h5>
                <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
            </div>
            <div class="modal-body" id="pnl_modal_body">
            </div>
        </div>
    </div>
</div>

<!-- LIGHTBOX MODAL -->
<div class="modal fade" id="lightboxModal" style="z-index:9999;">
    <div class="modal-dialog modal-xl modal-dialog-centered">
        <div class="modal-content" style="background: transparent; border: none; box-shadow: none;">
            <div class="modal-header" style="border: none; padding: 10px;">
                <button type="button" class="close text-white" data-dismiss="modal" style="font-size: 2.5rem; opacity: 1; text-shadow: 0 0 10px rgba(0,0,0,0.8);">&times;</button>
            </div>
            <div class="modal-body text-center p-0" id="lightbox_content">
            </div>
        </div>
    </div>
</div>

<!-- Include Chart.js -->
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
var currentProjectId = 0;
var budgetChartInstance = null;
var categoryChartInstance = null;
var isAdminUser = <?php echo $is_admin_user ? 'true' : 'false'; ?>;

// FIX FOR BOOTSTRAP MODAL STEALING FOCUS FROM SWEETALERT2
$.fn.modal.Constructor.prototype._enforceFocus = function() {};

$(document).ready(function() {
    var urlParams = new URLSearchParams(window.location.search);
    var urlPid = urlParams.get('project_id');
    
    if (urlPid) {
        $('#sel_project').val(urlPid);
    } else {
        var savedPid = localStorage.getItem('fin_selected_project');
        if (savedPid) {
            $('#sel_project').val(savedPid);
        }
    }
    
    // Restore active tab
    var activeTab = localStorage.getItem('fin_active_tab');
    if (activeTab) {
        $('.nav-pills a[href="' + activeTab + '"]').tab('show');
    }

    // Save active tab on click
    $('a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
        localStorage.setItem('fin_active_tab', $(e.target).attr('href'));
    });
    
    if ($('#sel_project').val()) {
        onProjectChange();
    }
});

function onProjectChange() {
    var pid = $('#sel_project').val();
    currentProjectId = parseInt(pid) || 0;
    if (!currentProjectId) {
        $('#main_area').hide();
        $('#main_nav_tabs').hide();
        $('#initial_project_selector').show();
        localStorage.removeItem('fin_selected_project');
        return;
    }
    localStorage.setItem('fin_selected_project', currentProjectId);
    $('#initial_project_selector').hide();
    $('#main_nav_tabs').show();
    $('#main_area').show();
    $('#sel_project_initial').val(currentProjectId);
    
    // Set hidden project inputs for modals
    $('#exp_project_id').val(currentProjectId);
    $('#pay_project_id').val(currentProjectId);
    $('#import_project_id').val(currentProjectId);
    $('#contract_project_id').val(currentProjectId);
    
    loadStageBudgets();
    loadExpenseCategories();
    loadExpenses();
    loadPayments();
    loadDashboard();
}


function loadExpenseCategories() {
    $.post('db-financial-info.php?ajax=get_expense_categories', {}, function(res) {
        var html = '<option value="">- Select -</option>';
        var filterHtml = '<option value="">All Categories</option>';
        (res || []).forEach(function(c) {
            html += '<option value="'+escapeHtml(c.category_name)+'">'+escapeHtml(c.category_name)+'</option>';
            filterHtml += '<option value="'+escapeHtml(c.category_name)+'">'+escapeHtml(c.category_name)+'</option>';
        });
        html += '<option value="ADD_NEW" style="font-weight:bold; color:#1d4ed8;">+ Add New Category</option>';
        $('#exp_category').html(html);
        if ($('#filter_exp_cat').length) $('#filter_exp_cat').html(filterHtml);
    }, 'json');
}

function handleCategoryChange(sel) {
    if (sel.value === 'ADD_NEW') {
        sel.value = ''; // Reset selection
        Swal.fire({
            title: 'Add New Category',
            input: 'text',
            inputPlaceholder: 'Enter category name...',
            showCancelButton: true,
            confirmButtonText: 'Add'
        }).then((result) => {
            if (result.isConfirmed && result.value) {
                $.post('db-financial-info.php?ajax=add_expense_category', {category_name: result.value}, function(res) {
                    if (res.success) {
                        loadExpenseCategories();
                        setTimeout(function(){ $('#exp_category').val(result.value); }, 500);
                    }
                }, 'json');
            }
        });
    }
}

function loadTasksForStage(sid) {
    if (!sid) {
        $('#exp_task_id').html('<option value="">- Select Stage First -</option>');
        return;
    }
    $.post('db-financial-info.php?ajax=get_tasks', {stage_id: sid}, function(tasks) {
        var html = '<option value="">- Select Task (Optional) -</option>';
        (tasks || []).forEach(function(t) {
            html += '<option value="'+t.id+'">'+escapeHtml(t.task_name)+'</option>';
        });
        $('#exp_task_id').html(html);
    }, 'json');
}

function populateStageDropdowns(stages) {
    var html = '<option value="">— Select Stage —</option>';
    var filterHtml = '<option value="">All Stages</option>';
    (stages || []).forEach(function(s) {
        html += '<option value="'+s.id+'">'+escapeHtml(s.stage_name)+'</option>';
        filterHtml += '<option value="'+s.id+'">'+escapeHtml(s.stage_name)+'</option>';
    });
    $('#exp_stage_id').html(html);
    $('#pay_stage_id').html(html);
    if ($('#filter_exp_stage').length) $('#filter_exp_stage').html(filterHtml);
    if ($('#filter_pay_stage').length) $('#filter_pay_stage').html(filterHtml);
}

function loadStageBudgets() {
    $('#budgets_tbody').html('<tr><td colspan="3" class="text-center text-muted"><i class="fas fa-spinner fa-spin"></i> Loading stages...</td></tr>');
    $.post('db-financial-info.php?ajax=get_stages_budget', {project_id: currentProjectId}, function(res) {
        populateStageDropdowns(res);
        var html = '';
        (res || []).forEach(function(s) {
            html += '<tr>';
            html += '<td><strong>' + escapeHtml(s.stage_name) + '</strong></td>';
            html += '<td><div class="input-group input-group-sm"><div class="input-group-prepend"><span class="input-group-text">₹</span></div><input type="number" class="form-control budget-alloc" data-id="'+s.id+'" value="'+(s.allocated_budget||'0.00')+'" step="0.01"></div></td>';
            html += '<td><div class="input-group input-group-sm"><div class="input-group-prepend"><span class="input-group-text">₹</span></div><input type="number" class="form-control budget-bill" data-id="'+s.id+'" value="'+(s.customer_billing_amount||'0.00')+'" step="0.01"></div></td>';
            html += '</tr>';
        });
        if (html === '') { html = '<tr><td colspan="3" class="text-center text-muted">No stages found. Add stages in the Tasks page first.</td></tr>'; }
        $('#budgets_tbody').html(html);
    }, 'json');
}

function loadDashboard() {
    $('#dashboard_content').html('<div class="card-panel" style="text-align:center; padding: 60px;"><i class="fas fa-spinner fa-spin" style="font-size:3rem; color:#cbd5e1; margin-bottom:15px;"></i><h4 style="color:#475569;">Loading Dashboard...</h4></div>');
    $.post('db-financial-info.php?ajax=get_dashboard_data', {project_id: currentProjectId}, function(res) {
        if (!res) return;
        
        var actual_profit = res.total_received - res.total_spent;
        var pnl = res.total_billing - res.total_spent;
        var pnl_bg = pnl >= 0 ? '#10b981' : '#ef4444';
        var pnl_label = pnl >= 0 ? 'Actual Profit' : 'Actual Loss';
        
        var budget_variance = res.total_budget - res.total_spent;
        var var_color = budget_variance >= 0 ? '#10b981' : '#ef4444';
        var var_text = budget_variance >= 0 ? 'Under Budget' : 'Over Budget';
        
        window.lastDashRes = res;
        
        var html = `
            <div class="row mb-4">
                <div class="col-lg col-md-4 col-sm-6 px-2 mb-3">
                    <div class="card-panel h-100" style="border-top:4px solid #3b82f6; cursor:pointer; text-align:center; padding:15px; margin-bottom:0; transition:transform 0.2s;" onclick="showCalculationModal('billing')" onmouseover="this.style.transform='translateY(-3px)'" onmouseout="this.style.transform='translateY(0)'">
                        <div style="display:flex; justify-content:center; align-items:center; gap:5px;">
                            <h6 style="color:#64748b; font-weight:600; font-size:10px; text-transform:uppercase; margin:0;">Contract Value <br><span style="font-size:8.5px; opacity:0.85; text-transform:none;">(Customer Billing)</span></h6>
                        </div>
                        <h3 style="color:#1e3a8a; font-weight:700; margin:8px 0; font-size:1.3rem;">₹${parseFloat(res.total_billing).toLocaleString('en-IN', {minimumFractionDigits:0})}</h3>
                        <small style="color:#3b82f6; font-size:10px; font-weight:600;"><i class="fas fa-hand-pointer mr-1"></i> View Calc</small>
                    </div>
                </div>
                <div class="col-lg col-md-4 col-sm-6 px-2 mb-3">
                    <div class="card-panel h-100" style="border-top:4px solid #f59e0b; cursor:pointer; text-align:center; padding:15px; margin-bottom:0; transition:transform 0.2s;" onclick="showCalculationModal('budget')" onmouseover="this.style.transform='translateY(-3px)'" onmouseout="this.style.transform='translateY(0)'">
                        <h6 style="color:#64748b; font-weight:600; font-size:10px; text-transform:uppercase; margin:0;">Int. Budget <br><span style="font-size:8.5px; opacity:0.85; text-transform:none;">(Estimated Cost)</span></h6>
                        <h3 style="color:#1e3a8a; font-weight:700; margin:8px 0; font-size:1.3rem;">₹${parseFloat(res.total_budget).toLocaleString('en-IN', {minimumFractionDigits:0})}</h3>
                        <small style="color:#3b82f6; font-size:10px; font-weight:600;"><i class="fas fa-hand-pointer mr-1"></i> View Calc</small>
                    </div>
                </div>
                <div class="col-lg col-md-4 col-sm-6 px-2 mb-3">
                    <div class="card-panel h-100" style="border-top:4px solid #8b5cf6; cursor:pointer; text-align:center; padding:15px; margin-bottom:0; transition:transform 0.2s;" onclick="showCalculationModal('expected_profit')" onmouseover="this.style.transform='translateY(-3px)'" onmouseout="this.style.transform='translateY(0)'">
                        <h6 style="color:#64748b; font-weight:600; font-size:10px; text-transform:uppercase;">Expected Profit</h6>
                        <h3 style="color:#1e3a8a; font-weight:700; margin:8px 0; font-size:1.3rem;">₹${parseFloat(res.expected_profit).toLocaleString('en-IN', {minimumFractionDigits:0})}</h3>
                        <small style="color:#3b82f6; font-size:10px; font-weight:600;"><i class="fas fa-hand-pointer mr-1"></i> View Calc</small>
                    </div>
                </div>
                <div class="col-lg col-md-4 col-sm-6 px-2 mb-3">
                    <div class="card-panel h-100" style="border-top:4px solid #06b6d4; cursor:pointer; text-align:center; padding:15px; margin-bottom:0; transition:transform 0.2s;" onclick="showCalculationModal('pending')" onmouseover="this.style.transform='translateY(-3px)'" onmouseout="this.style.transform='translateY(0)'">
                        <h6 style="color:#64748b; font-weight:600; font-size:10px; text-transform:uppercase;">Pending Collect</h6>
                        <h3 style="color:${res.pending_collections < 0 ? '#ef4444' : '#06b6d4'}; font-weight:700; margin:8px 0; font-size:1.3rem;">${res.pending_collections < 0 ? '-₹' : '₹'}${Math.abs(res.pending_collections).toLocaleString('en-IN', {minimumFractionDigits:0})}</h3>
                        <small style="color:#3b82f6; font-size:10px; font-weight:600;"><i class="fas fa-hand-pointer mr-1"></i> View Calc</small>
                    </div>
                </div>
                <div class="col-lg col-md-4 col-sm-6 px-2 mb-3">
                    <div class="card-panel h-100" style="border-top:4px solid ${actual_profit >= 0 ? '#10b981' : '#ef4444'}; cursor:pointer; text-align:center; padding:15px; margin-bottom:0; transition:transform 0.2s;" onclick="showCalculationModal('cashflow')" onmouseover="this.style.transform='translateY(-3px)'" onmouseout="this.style.transform='translateY(0)'">
                        <h6 style="color:#64748b; font-weight:600; font-size:10px; text-transform:uppercase;">Cashflow</h6>
                        <h3 style="color:${actual_profit >= 0 ? '#10b981' : '#ef4444'}; font-weight:700; margin:8px 0; font-size:1.3rem;">${actual_profit < 0 ? '-₹' : '₹'}${Math.abs(actual_profit).toLocaleString('en-IN', {minimumFractionDigits:0})}</h3>
                        <small style="color:#3b82f6; font-size:10px; font-weight:600;"><i class="fas fa-hand-pointer mr-1"></i> View Calc</small>
                    </div>
                </div>
                <div class="col-lg col-md-4 col-sm-6 px-2 mb-3">
                    <div class="card-panel h-100" style="background:${pnl_bg}; border:none; cursor:pointer; text-align:center; padding:15px; margin-bottom:0; transition:transform 0.2s;" onclick="showCalculationModal('net_profit')" onmouseover="this.style.transform='translateY(-3px)'" onmouseout="this.style.transform='translateY(0)'">
                        <h6 style="color:rgba(255,255,255,0.9); font-weight:600; font-size:10px; text-transform:uppercase;">${pnl_label}</h6>
                        <h3 style="color:#ffffff; font-weight:700; margin:8px 0; font-size:1.3rem;">₹${Math.abs(pnl).toLocaleString('en-IN', {minimumFractionDigits:0})}</h3>
                        <small style="color:rgba(255,255,255,0.8); font-size:10px; font-weight:600;"><i class="fas fa-hand-pointer mr-1"></i> View Calc</small>
                    </div>
                </div>
                <div class="col-lg col-md-4 col-sm-6 px-2 mb-3">
                    <div class="card-panel h-100" style="border-top:4px solid #ef4444; cursor:pointer; text-align:center; padding:15px; margin-bottom:0; transition:transform 0.2s;" onclick="showCalculationModal('variance')" onmouseover="this.style.transform='translateY(-3px)'" onmouseout="this.style.transform='translateY(0)'">
                        <h6 style="color:#ef4444; font-weight:600; font-size:10px; text-transform:uppercase;">Budget Variance</h6>
                        <h3 style="color:${var_color}; font-weight:700; margin:8px 0; font-size:1.3rem;">${budget_variance < 0 ? '-₹' : '₹'}${Math.abs(budget_variance).toLocaleString('en-IN', {minimumFractionDigits:0})}</h3>
                        <small style="color:#ef4444; font-size:10px; font-weight:600;">${var_text}</small>
                    </div>
                </div>
            </div>

            
            <div class="row mb-4">
                <div class="col-md-8">
                    <div class="card-panel">
                        <div class="section-title"><i class="fas fa-chart-bar"></i> Budget vs Spent (Per Stage)</div>
                        <canvas id="budgetChart" height="100"></canvas>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="card-panel">
                        <div class="section-title"><i class="fas fa-chart-pie"></i> Expense Breakdown</div>
                        <div style="position: relative; height: 250px; width: 100%;">
                            <canvas id="categoryChart"></canvas>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="card-panel">
                <div class="section-title"><i class="fas fa-layer-group"></i> Stage-wise Budget Tracking</div>
                <div class="table-responsive">
                    <table class="table table-hover">
                        <thead style="background:#f8fafc;">
                            <tr>
                                <th>Stage Name</th>
                                <th>Allocated Budget</th>
                                <th>Actual Spent</th>
                                <th>Variance (Status)</th>
                            </tr>
                        </thead>
                        <tbody>
        `;
        
        (res.stages || []).forEach(function(s) {
            var alloc = parseFloat(s.allocated_budget || 0);
            var spent = parseFloat(s.spent || 0);
            var diff = alloc - spent;
            
            var statusHtml = '';
            if (alloc === 0 && spent === 0) {
                statusHtml = '<span class="badge badge-light border text-muted">Not Started / No Budget</span>';
            } else if (diff < 0) {
                statusHtml = '<span class="badge" style="background:#fecdd3;color:#e11d48;font-size:12px;padding:6px 10px;"><i class="fas fa-exclamation-triangle"></i> Over Budget by ₹'+Math.abs(diff).toLocaleString('en-IN', {minimumFractionDigits:2})+'</span>';
            } else {
                statusHtml = '<span class="badge" style="background:#d1fae5;color:#059669;font-size:12px;padding:6px 10px;"><i class="fas fa-check"></i> Safe by ₹'+diff.toLocaleString('en-IN', {minimumFractionDigits:2})+'</span>';
            }
            
            html += `<tr style="cursor:pointer;" onclick="toggleStageDetails(${s.id || 0}, this)">
                <td style="font-weight:600; color:#1e3a8a;"><i class="fas fa-chevron-right mr-2 text-muted" style="font-size:10px;"></i>${escapeHtml(s.stage_name)}</td>
                <td style="color:#475569;">₹${alloc.toLocaleString('en-IN', {minimumFractionDigits:2})}</td>
                <td style="color:#ef4444; font-weight:700;">₹${spent.toLocaleString('en-IN', {minimumFractionDigits:2})}</td>
                <td>${statusHtml}</td>
            </tr>
            <tr id="details_${s.id || 0}" style="display:none; background:#f8fafc;">
                <td colspan="4" class="p-0 border-0">
                    <div class="p-3" style="border-left:4px solid #3b82f6; margin:10px;">
                        <div class="text-center"><i class="fas fa-spinner fa-spin text-muted"></i> Loading itemized P&L...</div>
                    </div>
                </td>
            </tr>`;
        });
        
        if (res.stages.length === 0) {
            html += '<tr><td colspan="4" class="text-center text-muted py-4">No stages found. Add stages to this project first.</td></tr>';
        }
        
        html += `</tbody></table></div></div>`;
        
        html += `
            <div class="card-panel mt-4">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;">
                    <div class="section-title" style="margin:0;"><i class="fas fa-file-alt"></i> Comprehensive Financial Report</div>
                    <div>
                        <button class="btn btn-sm btn-outline-secondary mr-2" onclick="printReport()"><i class="fas fa-print"></i> Print PDF</button>
                        <button class="btn btn-sm btn-outline-success" onclick="exportReportCSV()"><i class="fas fa-file-excel"></i> Export CSV</button>
                    </div>
                </div>
                <div id="financial_report_content" class="table-responsive">
                    <table class="table table-bordered table-sm" id="reportTable" style="font-size:13px; background:#fff;">
                        <thead style="background:#f1f5f9;">
                            <tr>
                                <th>Date</th>
                                <th>Stage / Context</th>
                                <th>Category</th>
                                <th>Description</th>
                                <th class="text-right">Amount (₹)</th>
                            </tr>
                        </thead>
                        <tbody>
        `;
        var totalReport = 0;
        window.allProjectExpenses = res.all_expenses || [];
        window.allProjectExpenses.forEach(function(e) {
            var context = e.stage_name ? escapeHtml(e.stage_name) : 'General Project Expense';
            if(e.task_name) context += ' — ' + escapeHtml(e.task_name);
            
            html += `<tr class="expense-row">
                <td>${escapeHtml(e.expense_date)}</td>
                <td style="color:#1e3a8a; font-weight:600;">${context}</td>
                <td><span class="badge badge-light border">${escapeHtml(e.expense_category)}</span></td>
                <td>${escapeHtml(e.description)}</td>
                <td class="text-right" style="color:#ef4444; font-weight:600;">${parseFloat(e.amount).toLocaleString('en-US', {minimumFractionDigits:2})}</td>
            </tr>`;
            totalReport += parseFloat(e.amount);
        });
        
        if (!res.all_expenses || res.all_expenses.length === 0) {
            html += '<tr><td colspan="5" class="text-center text-muted py-3">No expenses recorded for this project.</td></tr>';
        } else {
            html += `<tr style="background:#f8fafc;" id="grand_total_row">
                <td colspan="4" class="text-right" style="font-weight:700; color:#475569;">TOTAL:</td>
                <td class="text-right" style="font-weight:700; color:#e11d48; font-size:15px;" id="report_grand_total" data-original="${totalReport}">₹${totalReport.toLocaleString('en-US', {minimumFractionDigits:2})}</td>
            </tr>`;
        }
        
        html += `</tbody></table></div></div>`;
        
        $('#dashboard_content').html(html);
        
        // Render Charts
        if (budgetChartInstance) budgetChartInstance.destroy();
        if (categoryChartInstance) categoryChartInstance.destroy();
        
        var stgLabels = [];
        var stgAlloc = [];
        var stgSpent = [];
        var stgIds = [];
        (res.stages || []).forEach(function(s) {
            stgIds.push(s.id || 0);
            stgLabels.push(s.stage_name);
            stgAlloc.push(parseFloat(s.allocated_budget || 0));
            stgSpent.push(parseFloat(s.spent || 0));
        });
        
        var ctxBar = document.getElementById('budgetChart').getContext('2d');
        budgetChartInstance = new Chart(ctxBar, {
            type: 'bar',
            data: {
                labels: stgLabels,
                datasets: [
                    { label: 'Allocated Budget', backgroundColor: '#3b82f6', data: stgAlloc },
                    { label: 'Actual Spent', backgroundColor: '#ef4444', data: stgSpent }
                ]
            },
            options: { 
                responsive: true, 
                scales: { y: { beginAtZero: true } },
                onClick: function(e, elements) {
                    if (elements.length > 0) {
                        var index = elements[0].index;
                        var stageId = stgIds[index];
                        var targetRow = $('#details_' + stageId).prev('tr');
                        if(targetRow.length) {
                            $('html, body').animate({ scrollTop: targetRow.offset().top - 100 }, 500);
                            if(!$('#details_' + stageId).is(':visible')) {
                                targetRow.click();
                            }
                        }
                    }
                }
            }
        });
        
        var catLabels = [];
        var catData = [];
        var catColors = ['#f87171', '#fb923c', '#fbbf24', '#34d399', '#38bdf8', '#818cf8', '#c084fc', '#f472b6'];
        (res.categories || []).forEach(function(c) {
            catLabels.push(c.category);
            catData.push(c.total);
        });
        
        var ctxPie = document.getElementById('categoryChart').getContext('2d');
        categoryChartInstance = new Chart(ctxPie, {
            type: 'doughnut',
            data: {
                labels: catLabels,
                datasets: [{ data: catData, backgroundColor: catColors.slice(0, catData.length) }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                onClick: function(e, elements) {
                    if (elements.length > 0) {
                        var index = elements[0].index;
                        var clickedCategory = catLabels[index];
                        var target = $('#financial_report_content');
                        if (target.length) {
                            $('html, body').animate({ scrollTop: target.offset().top - 80 }, 500);
                            
                            var filteredTotal = 0;
                            $('#reportTable tbody tr.expense-row').each(function() {
                                var rowCat = $(this).find('td:eq(2)').text().trim();
                                if (rowCat !== clickedCategory) {
                                    $(this).hide();
                                } else {
                                    $(this).show();
                                    var amtText = $(this).find('td:eq(4)').text().replace(/[^0-9.-]+/g,"");
                                    filteredTotal += parseFloat(amtText || 0);
                                }
                            });
                            
                            $('#report_grand_total').html('₹' + filteredTotal.toLocaleString('en-US', {minimumFractionDigits:2}));
                            
                            if ($('#clear_cat_filter').length === 0) {
                                target.prepend('<div id="filter_notice" class="alert alert-info py-2" style="display:flex; justify-content:space-between; align-items:center;"><span><i class="fas fa-filter"></i> Filtering Report by Category: <strong>' + escapeHtml(clickedCategory) + '</strong></span> <button id="clear_cat_filter" class="btn btn-sm btn-light border" onclick="clearReportFilter()">Clear Filter</button></div>');
                            } else {
                                $('#filter_notice strong').text(clickedCategory);
                            }
                        }
                    }
                },
                plugins: { legend: { position: 'right', labels: { boxWidth: 12 } } }
            }
        });
        
    }, 'json');
}

function toggleStageDetails(stageId, rowElem) {
    var detailsRow = $('#details_' + stageId);
    var icon = $(rowElem).find('.fa-chevron-right, .fa-chevron-down');
    
    if (detailsRow.is(':visible')) {
        detailsRow.hide();
        icon.removeClass('fa-chevron-down').addClass('fa-chevron-right');
    } else {
        detailsRow.show();
        icon.removeClass('fa-chevron-right').addClass('fa-chevron-down');
        
        // Fetch P&L breakdown for this stage
        $.post('db-financial-info.php?ajax=get_stage_expenses', {project_id: currentProjectId, stage_id: stageId}, function(res) {
            var stgName = $(rowElem).find('td:first').text().replace(/[^a-zA-Z0-9 ]/g, '').trim();
            var html = '<div class="card-panel"><div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;"><h4 class="section-title mb-0"><i class="fas fa-file-invoice-dollar"></i> Expense Log</h4><div style="display:flex; gap:10px; align-items:center;"><input type="text" id="expenseSearch" class="form-control form-control-sm" placeholder="Filter expenses..." onkeyup="filterExpenses()" style="width: 200px;"><button class="btn btn-outline-info btn-sm" onclick="exportAllExpensesCSV()" style="font-weight:600;"><i class="fas fa-download mr-1"></i> Export CSV</button><button class="btn btn-outline-success btn-sm" onclick="$(\'#importExpModal\').modal(\'show\')" style="font-weight:600;"><i class="fas fa-file-excel mr-1"></i> Import</button><button class="btn btn-primary-custom btn-sm py-1" onclick="openExpenseModal()"><i class="fas fa-plus mr-1"></i> Add Expense</button></div></div>';
            html += '<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">';
            html += '<h6 style="color:#1e3a8a; font-weight:600; font-size:12px; text-transform:uppercase; margin:0;"><i class="fas fa-receipt mr-2"></i>Itemized Category Breakdown</h6>';
            if (res && res.length > 0) {
                html += '<button type="button" class="btn btn-sm btn-outline-success py-0 px-2" style="font-size:12px;" onclick="exportStageCSV('+stageId+', \''+stgName+'\')"><i class="fas fa-download mr-1"></i> Stage Report</button>';
            }
            html += '</div>';
            
            if (!res || res.length === 0) {
                html += '<p class="text-muted mb-0" style="font-size:13px;">No expenses recorded for this stage yet.</p>';
            } else {
                html += '<table class="table table-sm table-borderless mb-0" style="width:100%; min-width:300px;" id="stage_table_'+stageId+'">';
                var total = 0;
                res.forEach(function(c) {
                    html += '<tr><td style="color:#475569; font-size:13px;"><i class="fas fa-circle mr-2" style="font-size:6px; color:#94a3b8; vertical-align:middle;"></i>'+escapeHtml(c.expense_category)+' <a href="#financial_report_content" title="View Details in Main Report below" style="color:#cbd5e1; margin-left:8px; font-size:10px;"><i class="fas fa-external-link-alt"></i></a></td><td class="text-right" style="font-weight:600; color:#ef4444; font-size:13px;">₹'+parseFloat(c.total).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
                    total += parseFloat(c.total);
                });
                html += '<tr style="border-top:1px solid #e2e8f0;"><td style="font-weight:700; color:#1e3a8a; font-size:13px;">Total Spent</td><td class="text-right" style="font-weight:700; color:#e11d48; font-size:13px;">₹'+total.toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
                html += '</table>';
            }
            detailsRow.find('.p-3').html(html);
        }, 'json');
    }
}

function exportStageCSV(stageId, stageName) {
    if (!window.allProjectExpenses || window.allProjectExpenses.length === 0) {
        alert("No expense data available to download.");
        return;
    }
    
    var csv = ["Date,Category,Task/Context,Description,Amount Spent,Added By"];
    var found = false;
    
    window.allProjectExpenses.forEach(function(e) {
        if (parseInt(e.stage_id) === parseInt(stageId)) {
            found = true;
            var date = e.expense_date || '';
            var cat = (e.expense_category || '').replace(/"/g, '""');
            var ctx = (e.task_name ? e.task_name : 'General Stage Expense').replace(/"/g, '""');
            var desc = (e.description || '').replace(/"/g, '""');
            var amt = e.amount || '0';
            var addedBy = (e.added_by || 'System/Unknown').replace(/"/g, '""');
            
            csv.push('"' + date + '","' + cat + '","' + ctx + '","' + desc + '","' + amt + '","' + addedBy + '"');
        }
    });
    
    if (!found) {
        alert("No detailed line items found for this stage.");
        return;
    }
    
    var csvFile = new Blob([csv.join("\n")], {type: "text/csv;charset=utf-8;"});
    var downloadLink = document.createElement("a");
    downloadLink.download = "Stage_" + stageName.replace(/[^a-zA-Z0-9]/g, "_") + "_Detailed_Report.csv";
    downloadLink.href = window.URL.createObjectURL(csvFile);
    downloadLink.style.display = "none";
    document.body.appendChild(downloadLink);
    downloadLink.click();
}

function clearReportFilter() {
    $('#reportTable tbody tr.expense-row').show();
    $('#filter_notice').remove();
    var origTotal = $('#report_grand_total').attr('data-original');
    if (origTotal) {
        $('#report_grand_total').html('₹' + parseFloat(origTotal).toLocaleString('en-US', {minimumFractionDigits:2}));
    }
}

function exportAllExpensesCSV() {
    if (!window.rawExpensesData || window.rawExpensesData.length === 0) {
        alert("No expenses available to export.");
        return;
    }
    
    var csv = ["Date,Stage,Task,Category,Description,Amount Spent,Added By"];
    
    window.rawExpensesData.forEach(function(e) {
        var date = e.expense_date || '';
        var stage = (e.stage_name || 'General').replace(/"/g, '""');
        var task = (e.task_name || '').replace(/"/g, '""');
        var cat = (e.expense_category || '').replace(/"/g, '""');
        var desc = (e.description || '').replace(/"/g, '""');
        var amt = e.amount || '0';
        var addedBy = (e.added_by || 'System/Unknown').replace(/"/g, '""');
        
        csv.push('"' + date + '","' + stage + '","' + task + '","' + cat + '","' + desc + '","' + amt + '","' + addedBy + '"');
    });
    
    var csvFile = new Blob([csv.join("\n")], {type: "text/csv;charset=utf-8;"});
    var downloadLink = document.createElement("a");
    var projName = $("#sel_project option:selected").text().split('—')[0].trim().replace(/[^a-zA-Z0-9]/g, "_");
    downloadLink.download = "Project_" + projName + "_All_Expenses.csv";
    downloadLink.href = window.URL.createObjectURL(csvFile);
    downloadLink.style.display = "none";
    document.body.appendChild(downloadLink);
    downloadLink.click();
}

function showCalculationModal(type) {
    if(!window.lastDashRes) return;
    var res = window.lastDashRes;
    var html = '<table class="table table-bordered mb-3" style="font-size:14px;">';
    var note = '';
    var title = '';
    
    if (type === 'billing') {
        title = 'Contract Value Calculation';
        html += '<tr><td><strong>Fixed Contract Value</strong></td><td class="text-right text-primary" style="font-weight:600;">₹'+parseFloat(res.total_billing).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        html += '<tr><td><strong>Amount Received So Far</strong></td><td class="text-right text-success" style="font-weight:600;">₹'+parseFloat(res.total_received).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        var pending = res.total_billing - res.total_received;
        html += '<tr style="background:#f8fafc;"><td style="font-size:15px; font-weight:700;">Pending Collection</td><td class="text-right" style="font-size:16px; font-weight:700; color:#f59e0b;">₹'+pending.toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        note = 'This is the total agreed billing value for the project, regardless of actual expenses.';
    } 
    else if (type === 'budget') {
        title = 'Total Estimated Cost Calculation';
        html += '<tr><td><strong>Sum of Allocated Stage Budgets</strong></td><td class="text-right text-primary" style="font-weight:600;">₹'+parseFloat(res.total_budget).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        html += '<tr style="background:#f8fafc;"><td style="font-size:15px; font-weight:700;">TOTAL ESTIMATE</td><td class="text-right" style="font-size:16px; font-weight:700; color:#f59e0b;">₹'+parseFloat(res.total_budget).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        note = 'This is the sum of all estimated budgets allocated across all construction stages.';
    }
    else if (type === 'expected_profit') {
        title = 'Expected Profit Calculation';
        html += '<tr><td><strong>Contract Value (Billing)</strong></td><td class="text-right text-success" style="font-weight:600;">₹'+parseFloat(res.total_billing).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        html += '<tr><td><strong>Total Estimated Cost</strong></td><td class="text-right text-danger" style="font-weight:600;">- ₹'+parseFloat(res.total_budget).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        html += '<tr style="background:#f8fafc;"><td style="font-size:15px; font-weight:700;">EXPECTED PROFIT</td><td class="text-right" style="font-size:16px; font-weight:700; color:#8b5cf6;">₹'+parseFloat(res.expected_profit).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        note = 'This shows how much profit you expect to make IF you perfectly match your allocated estimated budgets without going over.';
    }
    else if (type === 'cashflow') {
        title = 'Cashflow Calculation';
        html += '<tr><td><strong>Total Amount Received (In)</strong></td><td class="text-right text-success" style="font-weight:600;">₹'+parseFloat(res.total_received).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        html += '<tr><td><strong>Total Amount Spent (Out)</strong></td><td class="text-right text-danger" style="font-weight:600;">- ₹'+parseFloat(res.total_spent).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        var cf = res.total_received - res.total_spent;
        var color = cf >= 0 ? '#10b981' : '#ef4444';
        html += '<tr style="background:#f8fafc;"><td style="font-size:15px; font-weight:700;">CASHFLOW</td><td class="text-right" style="font-size:16px; font-weight:700; color:'+color+';">₹'+cf.toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        note = 'Cashflow represents the actual money currently in your pocket (Money Received vs Money Spent).';
    }
    else if (type === 'net_profit' || type === 'net_loss') {
        title = 'Actual Profit / Loss Calculation';
        html += '<tr><td><strong>Contract Value (Total Billing)</strong></td><td class="text-right text-success" style="font-weight:600;">₹'+parseFloat(res.total_billing).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        html += '<tr><td><strong>Total Amount Spent</strong></td><td class="text-right text-danger" style="font-weight:600;">- ₹'+parseFloat(res.total_spent).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        
        var bal = res.total_billing - res.total_spent;
        var color = bal >= 0 ? '#10b981' : '#ef4444';
        var text = bal >= 0 ? 'NET PROFIT' : 'NET LOSS';
        
        html += '<tr style="background:#f8fafc;"><td style="font-size:16px; font-weight:700;">'+text+'</td><td class="text-right" style="font-size:18px; font-weight:700; color:'+color+';">₹'+Math.abs(bal).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        note = 'This Profit & Loss calculation is based solely on your total contract value minus the actual expenses incurred so far.';
    }
    else if (type === 'variance') {
        title = 'Budget Variance Calculation';
        html += '<tr><td><strong>Internal Budget (Estimated Cost)</strong></td><td class="text-right text-primary" style="font-weight:600;">₹'+parseFloat(res.total_budget).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        html += '<tr><td><strong>Actual Spent</strong></td><td class="text-right text-danger" style="font-weight:600;">- ₹'+parseFloat(res.total_spent).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        var variance = res.total_budget - res.total_spent;
        var color = variance >= 0 ? '#10b981' : '#ef4444';
        html += '<tr style="background:#f8fafc;"><td style="font-size:15px; font-weight:700;">BUDGET VARIANCE</td><td class="text-right" style="font-size:16px; font-weight:700; color:'+color+';">₹'+Math.abs(variance).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        note = 'This tracks if your actual spending is staying under the internal budget limits. Red means you overspent!';
    }
    else if (type === 'pending') {
        title = 'Pending Collection Calculation';
        html += '<tr><td><strong>Contract Value (Customer Billing)</strong></td><td class="text-right text-primary" style="font-weight:600;">₹'+parseFloat(res.total_billing).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        html += '<tr><td><strong>Total Received</strong></td><td class="text-right text-success" style="font-weight:600;">- ₹'+parseFloat(res.total_received).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        var pending = res.total_billing - res.total_received;
        var color = pending >= 0 ? '#f59e0b' : '#ef4444';
        var text = pending >= 0 ? 'PENDING TO COLLECT' : 'OVERPAID (REFUND DUE)';
        html += '<tr style="background:#f8fafc;"><td style="font-size:15px; font-weight:700;">'+text+'</td><td class="text-right" style="font-size:16px; font-weight:700; color:'+color+';">₹'+Math.abs(pending).toLocaleString('en-US', {minimumFractionDigits:2})+'</td></tr>';
        note = 'This shows the remaining balance the customer owes you based on the contract value.';
    }
    
    html += '</table>';
    html += '<div class="alert alert-info" style="font-size:13px;"><i class="fas fa-info-circle mr-1"></i> <strong>Note:</strong> ' + note + '</div>';
    
    $('#calc_modal_title').html('<i class="fas fa-calculator mr-2"></i>' + title);
    $('#pnl_modal_body').html(html);
    $('#pnlModal').modal('show');
}

function printReport() {
    var printContents = document.getElementById('financial_report_content').innerHTML;
    var originalContents = document.body.innerHTML;
    document.body.innerHTML = "<h2 style='text-align:center;font-family:sans-serif;margin-bottom:20px;'>Project Financial Report</h2>" + printContents;
    window.print();
    document.body.innerHTML = originalContents;
    window.location.reload(); 
}

function exportReportCSV() {
    var table = document.getElementById("reportTable");
    if(!table) return;
    var csv = [];
    var rows = table.querySelectorAll("tr");
    for (var i = 0; i < rows.length; i++) {
        var row = [], cols = rows[i].querySelectorAll("td, th");
        for (var j = 0; j < cols.length; j++) {
            var data = cols[j].innerText.replace(/(\r\n|\n|\r)/gm, "").replace(/(\s\s)/gm, " ");
            data = data.replace(/"/g, '""');
            row.push('"' + data + '"');
        }
        csv.push(row.join(","));
    }
    var csvFile = new Blob([csv.join("\n")], {type: "text/csv"});
    var downloadLink = document.createElement("a");
    downloadLink.download = "Financial_Report_Proj_" + currentProjectId + ".csv";
    downloadLink.href = window.URL.createObjectURL(csvFile);
    downloadLink.style.display = "none";
    document.body.appendChild(downloadLink);
    downloadLink.click();
}

function saveStageBudgets() {
    var budgets = [];
    $('.budget-alloc').each(function() {
        var id = $(this).data('id');
        var alloc = $(this).val();
        var bill = $('.budget-bill[data-id="'+id+'"]').val();
        budgets.push({id: id, allocated: alloc, billing: bill});
    });
    
    var btn = $(event.currentTarget);
    var oldHtml = btn.html();
    btn.prop('disabled', true).html('<i class="fas fa-spinner fa-spin mr-2"></i>Saving...');
    
    $.post('db-financial-info.php?ajax=save_stage_budgets', {project_id: currentProjectId, budgets: budgets}, function(res) {
        btn.prop('disabled', false).html(oldHtml);
        if (res && res.success) {
            Swal.fire({icon:'success', title:'Budgets Saved', timer:1500, showConfirmButton:false});
            loadStageBudgets();
        } else {
            Swal.fire({icon:'error', title:'Error', text:res.msg||'Failed to save'});
        }
    }, 'json');
}

// ==========================================
// EXPENSES
// ==========================================
function toggleExpenseScope() {
    var scope = $('input[name="expense_scope"]:checked').val();
    if (scope === 'stage') {
        $('#row_stage_task').show();
        $('#exp_stage_id').prop('required', true);
    } else {
        $('#row_stage_task').hide();
        $('#exp_stage_id').prop('required', false);
        $('#exp_stage_id').val('');
        $('#exp_task_id').html('<option value="">- Select Stage First -</option>');
    }
}

window.rawExpensesData = {};
window.expensesList = [];

function loadExpenses() {
    $('#expenses_tbody').html('<tr><td colspan="7" class="text-center"><i class="fas fa-spinner fa-spin"></i> Loading...</td></tr>');
    $.post('db-financial-info.php?ajax=get_expenses', {project_id: currentProjectId}, function(res) {
        window.expensesList = res || [];
        window.rawExpensesData = {};
        window.expensesList.forEach(function(e) { window.rawExpensesData[e.id] = e; });
        applyExpenseFilter();
    }, 'json');
}

function applyExpenseFilter() {
    var html = '';
    var fromDate = $('#filter_exp_from').val();
    var toDate = $('#filter_exp_to').val();
    var cat = $('#filter_exp_cat').val();
    var stageId = $('#filter_exp_stage').val();

    window.expensesList.forEach(function(e) {
        if (fromDate && e.expense_date < fromDate) return;
        if (toDate && e.expense_date > toDate) return;
        if (cat && e.expense_category !== cat) return;
        if (stageId && String(e.stage_id) !== String(stageId)) return;

        var stg = e.stage_name ? escapeHtml(e.stage_name) : '<i>General Project</i>';
        if(e.task_name) stg += '<br><small class="text-muted">' + escapeHtml(e.task_name) + '</small>';
        
        var proofs = '';
        if (e.proof_file) {
            var files = e.proof_file.split(',');
            files.forEach(function(f, i) {
                var fName = f.split('/').pop();
                var ext = fName.split('.').pop().toLowerCase();
                var isImg = ['jpg','jpeg','png','gif','webp'].includes(ext);
                proofs += '<div class="mb-1" style="display:flex; align-items:center; gap:5px;">';
                if (isImg) {
                    proofs += '<a href="javascript:void(0)" onclick="viewFileLightbox(\''+f+'\')" title="View Image"><img src="'+f+'" style="height:35px; width:35px; object-fit:cover; border-radius:4px; border:1px solid #cbd5e1;"></a>';
                } else {
                    proofs += '<a href="javascript:void(0)" onclick="viewFileLightbox(\''+f+'\')" class="badge badge-light border d-inline-block" title="View"><i class="fas fa-eye"></i></a>';
                }
                proofs += '<a href="'+f+'" download="'+fName+'" class="badge badge-info border d-inline-block" title="Download"><i class="fas fa-download"></i> DL</a></div>';
            });
        } else { proofs = '<span class="text-muted">-</span>'; }

        html += '<tr>';
        html += '<td><input type="checkbox" class="chk-expense" value="'+e.id+'" onchange="toggleExpenseSelection()"></td>';
        html += '<td>'+escapeHtml(e.expense_date)+'</td>';
        html += '<td>'+stg+'</td>';
        html += '<td><span class="badge badge-secondary">'+escapeHtml(e.expense_category)+'</span></td>';
        html += '<td>'+escapeHtml(e.description)+'</td>';
        html += '<td style="color:#e11d48;font-weight:700;">₹'+parseFloat(e.amount).toLocaleString('en-US', {minimumFractionDigits:2})+'</td>';
        html += '<td>'+proofs+'</td>';
        
        var statusHtml = '';
        var expStatus = e.status || 'Approved';
        if (expStatus === 'Under Review') expStatus = 'Approved';

        if (expStatus === 'Approved') {
            statusHtml = '<span class="badge badge-success"><i class="fas fa-check-circle"></i> Approved</span>';
        } else if (expStatus === 'Declined') {
            statusHtml = '<span class="badge badge-danger"><i class="fas fa-times-circle"></i> Declined</span>';
            if (e.manager_reason) statusHtml += '<br><small class="text-danger" style="display:block;margin-top:4px;line-height:1.2;">'+escapeHtml(e.manager_reason)+'</small>';
        }
        
        html += '<td>'+statusHtml+'</td>';

        html += '<td style="white-space:nowrap;">';
        html += '<button class="btn btn-sm btn-outline-secondary mr-1" onclick="printSingleVoucher('+e.id+')" title="Print Voucher"><i class="fas fa-print"></i></button>';
        if (isAdminUser) {
            if (expStatus === 'Approved') {
                html += '<button class="btn btn-sm btn-outline-warning mr-1" onclick="reviewExpense('+e.id+', \'Declined\')" title="Decline Expense"><i class="fas fa-times-circle"></i></button>';
            } else if (expStatus === 'Declined') {
                html += '<button class="btn btn-sm btn-outline-success mr-1" onclick="reviewExpense('+e.id+', \'Approved\')" title="Restore Expense"><i class="fas fa-undo"></i></button>';
            }
        }
        html += '<button class="btn btn-sm btn-outline-primary mr-1" onclick="editExpense('+e.id+')" title="Edit"><i class="fas fa-edit"></i></button>';
        html += '<button class="btn btn-sm btn-outline-danger" onclick="deleteExpense('+e.id+')" title="Delete"><i class="fas fa-trash"></i></button>';
        html += '</td>';
        html += '</tr>';
    });
    if(html==='') html='<tr><td colspan="7" class="text-center">No expenses match the filter criteria.</td></tr>';
    $('#expenses_tbody').html(html);
}

function resetExpenseFilter() {
    $('#filter_exp_from').val('');
    $('#filter_exp_to').val('');
    $('#filter_exp_cat').val('');
    $('#filter_exp_stage').val('');
    applyExpenseFilter();
}

function openExpenseModal() {
    $('#expenseForm')[0].reset();
    $('#exp_edit_id').val(0);
    $('#exp_modal_title').text('Add Expense');
    
    // Set default date to today
    var today = new Date();
    var dd = String(today.getDate()).padStart(2, '0');
    var mm = String(today.getMonth() + 1).padStart(2, '0');
    var yyyy = today.getFullYear();
    $('#exp_date').val(yyyy + '-' + mm + '-' + dd);

    $('#lbl_exp_proof').text('Upload Bill/Receipt *');
    clearExpenseProof();
    $('#type_stage').prop('checked', true);
    toggleExpenseScope();
    $('#expenseModal').modal('show');
}

function editExpense(id) {
    var e = window.rawExpensesData[id];
    if(!e) return;
    $('#expenseForm')[0].reset();
    $('#exp_edit_id').val(e.id);
    $('#exp_modal_title').text('Edit Expense');
    
    clearExpenseProof();
    $('#lbl_exp_proof').html('Upload Bill/Receipt <i>(Optional during Edit)</i>');

    if (e.proof_file) {
        $('#exp_proof_selected').css('display', 'flex');
        $('#exp_proof_selected span').text('Existing Proofs (Upload new to append)');
        var container = $('#exp_proof_preview_container');
        var files = e.proof_file.split(',');
        files.forEach(function(f) {
            var ext = f.split('.').pop().toLowerCase();
            var wrapper = $('<div class="existing-proof-item" style="position:relative; display:inline-block;"></div>');
            var removeBtn = $('<button type="button" class="btn btn-sm btn-danger p-0" style="position:absolute; top:-5px; right:-5px; width:20px; height:20px; border-radius:50%; font-size:10px; z-index:10;" onclick="removeExistingProof(\''+f+'\', this)"><i class="fas fa-times"></i></button>');
            if (['jpg','jpeg','png','gif','webp'].includes(ext)) {
                wrapper.append('<img src="'+f+'" style="height:60px; border-radius:5px; border:1px solid #ccc; object-fit:cover;">');
            } else {
                wrapper.append('<div style="height:60px; width:50px; display:flex; align-items:center; justify-content:center; background:#f8fafc; border:1px solid #cbd5e1; border-radius:5px; color:#ef4444;"><i class="fas fa-file-pdf fa-2x"></i></div>');
            }
            wrapper.append(removeBtn);
            container.append(wrapper);
        });
    }
    
    if (e.stage_id && e.stage_id > 0) {
        $('#type_stage').prop('checked', true);
        toggleExpenseScope();
        $('#exp_stage_id').val(e.stage_id);
        loadTasksForStage(e.stage_id);
        setTimeout(function() { $('#exp_task_id').val(e.task_id); }, 500);
    } else {
        $('#type_general').prop('checked', true);
        toggleExpenseScope();
    }
    
    $('#exp_category').val(e.expense_category);
    $('#exp_date').val(e.expense_date);
    $('#exp_amount').val(e.amount);
    $('#exp_description').val(e.description);
    
    $('#expenseModal').modal('show');
}

function saveExpense(e) {
    e.preventDefault();
    var editId = parseInt($('#exp_edit_id').val()) || 0;
    var camFiles = document.getElementById('exp_proof_camera').files.length;
    var galFiles = document.getElementById('exp_proof_gallery').files.length;
    if (editId === 0 && camFiles === 0 && galFiles === 0) {
        Swal.fire('Required', 'Please take a photo or select a file for the receipt proof.', 'warning');
        return;
    }
    
    var fd = new FormData(document.getElementById('expenseForm'));
    $('#btn_save_exp').prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i> Saving...');
    $.ajax({
        url: 'db-financial-info.php?ajax=save_expense',
        type: 'POST', data: fd, processData: false, contentType: false,
        success: function(res) {
            $('#btn_save_exp').prop('disabled', false).html('<i class="fas fa-save"></i> Save');
            if(res.success) {
                $('#expenseModal').modal('hide');
                Swal.fire({icon:'success', title:'Saved', timer:1500, showConfirmButton:false});
                loadExpenses();
            } else { Swal.fire('Error', res.msg||'Failed to save', 'error'); }
        }, dataType: 'json'
    });
}

function deleteExpense(id) {
    Swal.fire({
        title: 'Delete Expense?', text: "This will permanently remove the record.", icon: 'warning',
        showCancelButton: true, confirmButtonColor: '#e11d48', confirmButtonText: 'Yes, delete it!'
    }).then((result) => {
        if(result.isConfirmed) {
            $.post('db-financial-info.php?ajax=delete_expense', {id: id}, function(res) {
                if(res.success) { loadExpenses(); loadDashboard(); }
            }, 'json');
        }
    });
}

function reviewExpense(id, status) {
    if (status === 'Declined') {
        Swal.fire({
            title: 'Decline Expense',
            input: 'textarea',
            inputLabel: 'Reason for declining',
            inputPlaceholder: 'Type your reason here...',
            inputAttributes: {
                'aria-label': 'Type your reason here'
            },
            showCancelButton: true,
            confirmButtonText: 'Decline',
            confirmButtonColor: '#ef4444',
            inputValidator: (value) => {
                if (!value) {
                    return 'You need to write something!'
                }
            }
        }).then((result) => {
            if (result.isConfirmed) {
                submitExpenseReview(id, status, result.value);
            }
        });
    } else {
        Swal.fire({
            title: 'Restore Expense?',
            text: "This will approve the expense and re-add it to the project calculations.",
            icon: 'question',
            showCancelButton: true,
            confirmButtonColor: '#10b981',
            confirmButtonText: 'Yes, Restore it!'
        }).then((result) => {
            if (result.isConfirmed) {
                submitExpenseReview(id, status, '');
            }
        });
    }
}

function submitExpenseReview(id, status, reason) {
    $.post('db-financial-info.php?ajax=review_expense', {
        id: id,
        status: status,
        reason: reason
    }, function(res) {
        if(res.success) {
            Swal.fire('Success', 'Expense status updated.', 'success');
            loadExpenses();
            loadDashboard(); // update totals
        } else {
            Swal.fire('Error', res.msg || 'Failed to update.', 'error');
        }
    }, 'json');
}

function importExpenses(e) {
    e.preventDefault();
    var fd = new FormData(document.getElementById('importExpForm'));
    $('#btn_import_exp').prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i> Uploading...');
    $.ajax({
        url: 'db-financial-info.php?ajax=import_expenses',
        type: 'POST', data: fd, processData: false, contentType: false,
        success: function(res) {
            $('#btn_import_exp').prop('disabled', false).html('<i class="fas fa-upload"></i> Upload & Import');
            if(res.success) {
                $('#importExpModal').modal('hide');
                Swal.fire({icon:'success', title:'Import Successful', text:res.msg});
                loadExpenses();
                loadDashboard();
            } else { Swal.fire('Error', res.msg||'Failed to import', 'error'); }
        }, dataType: 'json'
    });
}

// ==========================================
// PAYMENTS
// ==========================================
function togglePayStage() {
    var type = $('#pay_type').val();
    if(type === 'Stage Payment') $('#div_pay_stage').show();
    else $('#div_pay_stage').hide();
}

window.rawPaymentsData = {};
window.paymentsList = [];

function loadPayments() {
    $('#payments_tbody').html('<tr><td colspan="7" class="text-center"><i class="fas fa-spinner fa-spin"></i> Loading...</td></tr>');
    $.post('db-financial-info.php?ajax=get_payments', {project_id: currentProjectId}, function(res) {
        window.paymentsList = res || [];
        window.rawPaymentsData = {};
        window.paymentsList.forEach(function(p) { window.rawPaymentsData[p.id] = p; });
        applyPaymentFilter();
    }, 'json');
}

function applyPaymentFilter() {
    var html = '';
    var fromDate = $('#filter_pay_from').val();
    var toDate = $('#filter_pay_to').val();
    var stageId = $('#filter_pay_stage').val();

    window.paymentsList.forEach(function(p) {
        if (fromDate && p.payment_date < fromDate) return;
        if (toDate && p.payment_date > toDate) return;
        if (stageId && String(p.stage_id) !== String(stageId) && p.payment_type === 'Stage Payment') return;

        var stg = p.stage_name ? ' - ' + escapeHtml(p.stage_name) : '';
        
        var proofs = '';
        if (p.proof_file) {
            var files = p.proof_file.split(',');
            files.forEach(function(f, i) {
                var fName = f.split('/').pop();
                var ext = fName.split('.').pop().toLowerCase();
                var isImg = ['jpg','jpeg','png','gif','webp'].includes(ext);
                proofs += '<div class="mb-1" style="display:flex; align-items:center; gap:5px;">';
                if (isImg) {
                    proofs += '<a href="javascript:void(0)" onclick="viewFileLightbox(\''+f+'\')" title="View Image"><img src="'+f+'" style="height:35px; width:35px; object-fit:cover; border-radius:4px; border:1px solid #cbd5e1;"></a>';
                } else {
                    proofs += '<a href="javascript:void(0)" onclick="viewFileLightbox(\''+f+'\')" class="badge badge-light border d-inline-block" title="View"><i class="fas fa-eye"></i></a>';
                }
                proofs += '<a href="'+f+'" download="'+fName+'" class="badge badge-info border d-inline-block" title="Download"><i class="fas fa-download"></i> DL</a></div>';
            });
        } else { proofs = '<span class="text-muted">-</span>'; }

        html += '<tr>';
        html += '<td>'+escapeHtml(p.payment_date)+'</td>';
        html += '<td><strong>'+escapeHtml(p.payment_type)+'</strong>'+stg+'</td>';
        html += '<td>'+escapeHtml(p.payment_mode)+'</td>';
        html += '<td>'+escapeHtml(p.reference_no)+'<br><small class="text-muted">'+escapeHtml(p.notes)+'</small></td>';
        html += '<td style="color:#059669;font-weight:700;">₹'+parseFloat(p.amount).toLocaleString('en-US', {minimumFractionDigits:2})+'</td>';
        html += '<td>'+proofs+'</td>';
        html += '<td>';
        html += '<button class="btn btn-sm btn-outline-primary mr-1" onclick="editPayment('+p.id+')" title="Edit"><i class="fas fa-edit"></i></button>';
        html += '<button class="btn btn-sm btn-outline-danger" onclick="deletePayment('+p.id+')" title="Delete"><i class="fas fa-trash"></i></button>';
        html += '</td>';
        html += '</tr>';
    });
    if(html==='') html='<tr><td colspan="7" class="text-center">No payments match the filter criteria.</td></tr>';
    $('#payments_tbody').html(html);
}

function resetPaymentFilter() {
    $('#filter_pay_from').val('');
    $('#filter_pay_to').val('');
    $('#filter_pay_stage').val('');
    applyPaymentFilter();
}

function openPaymentModal() {
    $('#paymentForm')[0].reset();
    $('#pay_edit_id').val(0);
    $('#pay_modal_title').text('Add Payment');
    $('#lbl_pay_proof').text('Upload Receipt/Screenshot *');
    $('#pay_proof_camera').val('');
    $('#pay_proof_gallery').val('');
    $('#pay_proof_selected').hide();
    togglePayStage();
    $('#paymentModal').modal('show');
}

function editPayment(id) {
    var p = window.rawPaymentsData[id];
    if(!p) return;
    $('#paymentForm')[0].reset();
    $('#pay_edit_id').val(p.id);
    $('#pay_modal_title').text('Edit Payment');
    $('#lbl_pay_proof').text('Upload Receipt/Screenshot (Optional during Edit)');
    $('#pay_proof_camera').val('');
    $('#pay_proof_gallery').val('');
    $('#pay_proof_selected').hide();
    
    $('#pay_type').val(p.payment_type);
    togglePayStage();
    if(p.payment_type === 'Stage Payment') {
        $('#pay_stage_id').val(p.stage_id);
    }
    
    $('#pay_date').val(p.payment_date);
    $('#pay_amount').val(p.amount);
    $('#pay_mode').val(p.payment_mode);
    $('#pay_ref').val(p.reference_no);
    $('#pay_notes').val(p.notes);
    
    $('#paymentModal').modal('show');
}

function savePayment(e) {
    e.preventDefault();
    var editId = parseInt($('#pay_edit_id').val()) || 0;
    var camFiles = document.getElementById('pay_proof_camera').files.length;
    var galFiles = document.getElementById('pay_proof_gallery').files.length;
    if (editId === 0 && camFiles === 0 && galFiles === 0) {
        Swal.fire('Required', 'Please take a photo or select a file for the payment proof.', 'warning');
        return;
    }
    
    var fd = new FormData(document.getElementById('paymentForm'));
    $('#btn_save_pay').prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i> Saving...');
    $.ajax({
        url: 'db-financial-info.php?ajax=save_payment',
        type: 'POST', data: fd, processData: false, contentType: false,
        success: function(res) {
            $('#btn_save_pay').prop('disabled', false).html('<i class="fas fa-save"></i> Save');
            if(res.success) {
                $('#paymentModal').modal('hide');
                Swal.fire({icon:'success', title:'Saved', timer:1500, showConfirmButton:false});
                loadPayments();
            } else { Swal.fire('Error', res.msg||'Failed to save', 'error'); }
        }, dataType: 'json'
    });
}

function deletePayment(id) {
    Swal.fire({
        title: 'Delete Payment?', text: "This will permanently remove the record.", icon: 'warning',
        showCancelButton: true, confirmButtonColor: '#e11d48', confirmButtonText: 'Yes, delete it!'
    }).then((result) => {
        if(result.isConfirmed) {
            $.post('db-financial-info.php?ajax=delete_payment', {id: id}, function(res) {
                if(res.success) loadPayments();
            }, 'json');
        }
    });
}

function escapeHtml(text) {
    if (!text) return '';
    return text.toString()
         .replace(/&/g, "&amp;")
         .replace(/</g, "&lt;")
         .replace(/>/g, "&gt;")
         .replace(/"/g, "&quot;")
         .replace(/'/g, "&#039;");
}

function viewFileLightbox(url) {
    var ext = url.split('.').pop().toLowerCase();
    var isImg = ['jpg','jpeg','png','gif','webp'].includes(ext);
    var content = '';
    if (isImg) {
        content = '<img src="'+url+'" style="max-width: 100%; max-height: 85vh; border-radius: 8px; box-shadow: 0 5px 30px rgba(0,0,0,0.5); object-fit: contain;">';
    } else {
        content = '<iframe src="'+url+'" style="width: 100%; height: 85vh; border: none; border-radius: 8px; box-shadow: 0 5px 30px rgba(0,0,0,0.5); background: white;"></iframe>';
    }
    $('#lightbox_content').html(content);
    $('#lightboxModal').modal('show');
}

function filterExpenses() {
    var value = $('#expenseSearch').val().toLowerCase();
    $('#expenses_tbody tr').each(function() {
        if ($(this).find('td[colspan]').length > 0) return; // skip 'no records' row
        var text = $(this).text().toLowerCase();
        $(this).toggle(text.indexOf(value) > -1);
    });
}

function filterPayments() {
    var value = $('#paymentSearch').val().toLowerCase();
    $('#payments_tbody tr').each(function() {
        if ($(this).find('td[colspan]').length > 0) return; // skip 'no records' row
        var text = $(this).text().toLowerCase();
        $(this).toggle(text.indexOf(value) > -1);
    });
}

function openContractModal() {
    $('#contract_project_id').val(currentProjectId);
    $('#contract_val_input').val('');
    if(window.lastDashRes && window.lastDashRes.total_billing) {
        $('#contract_val_input').val(window.lastDashRes.total_billing);
    }
    $('#contractModal').modal('show');
}

function saveContractValue(e) {
    e.preventDefault();
    var fd = new FormData(document.getElementById('contractForm'));
    $('#btn_save_contract').prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i> Saving...');
    $.ajax({
        url: 'db-financial-info.php?ajax=set_contract_value',
        type: 'POST', data: fd, processData: false, contentType: false,
        success: function(res) {
            $('#btn_save_contract').prop('disabled', false).html('<i class="fas fa-save mr-1"></i> Save Budget');
            if(res.success) {
                $('#contractModal').modal('hide');
                Swal.fire({icon:'success', title:'Budget Updated', timer:1500, showConfirmButton:false});
                loadDashboard();
            } else { Swal.fire('Error', res.msg||'Failed to save', 'error'); }
        }, dataType: 'json'
    });
}

function clearExpenseProof() {
    $('#exp_proof_camera').val('');
    $('#exp_proof_gallery').val('');
    $('#exp_proof_selected').hide();
    $('#exp_proof_preview_container').html('');
    $('#lbl_exp_proof').html('Upload Bill/Receipt *');
    $('#removed_existing_proofs_container').html('');
}

function removeNewProof(index, inputId) {
    var input = document.getElementById(inputId);
    var dt = new DataTransfer();
    for(var i=0; i<input.files.length; i++) {
        if(i !== index) dt.items.add(input.files[i]);
    }
    input.files = dt.files;
    handleExpenseProofSelect(input);
}

function removeExistingProof(path, btn) {
    $('#removed_existing_proofs_container').append('<input type="hidden" name="removed_existing_proofs[]" value="'+escapeHtml(path)+'">');
    $(btn).closest('.existing-proof-item').remove();
}

function handleExpenseProofSelect(input) {
    if (input.files && input.files.length > 0) {
        $('#exp_proof_selected').css('display','flex');
        $('#lbl_exp_proof').html('Proof <i class=\'fas fa-check text-success\'></i>');
        var container = $('#exp_proof_preview_container');
        container.html('');
        Array.from(input.files).forEach((file, index) => {
            var wrapper = $('<div style="position:relative; display:inline-block;"></div>');
            var removeBtn = $('<button type="button" class="btn btn-sm btn-danger p-0" style="position:absolute; top:-5px; right:-5px; width:20px; height:20px; border-radius:50%; font-size:10px; z-index:10;" onclick="removeNewProof('+index+', \''+input.id+'\')"><i class="fas fa-times"></i></button>');
            
            if (file.type.startsWith('image/')) {
                var reader = new FileReader();
                reader.onload = function(e) {
                    wrapper.append('<img src="'+e.target.result+'" style="height:60px; border-radius:5px; border:1px solid #ccc; object-fit:cover;">');
                    wrapper.append(removeBtn);
                    container.append(wrapper);
                }
                reader.readAsDataURL(file);
            } else if (file.type === 'application/pdf') {
                wrapper.append('<div style="height:60px; width:50px; display:flex; align-items:center; justify-content:center; background:#f8fafc; border:1px solid #cbd5e1; border-radius:5px; color:#ef4444;"><i class="fas fa-file-pdf fa-2x"></i></div>');
                wrapper.append(removeBtn);
                container.append(wrapper);
            }
        });
    } else {
        $('#exp_proof_selected').hide();
        $('#exp_proof_preview_container').html('');
        $('#lbl_exp_proof').html('Upload Bill/Receipt *');
    }
}

function numberToWords(num) {
    var a = ['','One ','Two ','Three ','Four ', 'Five ','Six ','Seven ','Eight ','Nine ','Ten ','Eleven ','Twelve ','Thirteen ','Fourteen ','Fifteen ','Sixteen ','Seventeen ','Eighteen ','Nineteen '];
    var b = ['', '', 'Twenty','Thirty','Forty','Fifty', 'Sixty','Seventy','Eighty','Ninety'];
    if ((num = num.toString()).length > 9) return 'overflow';
    var n = ('000000000' + num).substr(-9).match(/^(\d{2})(\d{2})(\d{2})(\d{1})(\d{2})$/);
    if (!n) return; var str = '';
    str += (n[1] != 0) ? (a[Number(n[1])] || b[n[1][0]] + ' ' + a[n[1][1]]) + 'Crore ' : '';
    str += (n[2] != 0) ? (a[Number(n[2])] || b[n[2][0]] + ' ' + a[n[2][1]]) + 'Lakh ' : '';
    str += (n[3] != 0) ? (a[Number(n[3])] || b[n[3][0]] + ' ' + a[n[3][1]]) + 'Thousand ' : '';
    str += (n[4] != 0) ? (a[Number(n[4])] || b[n[4][0]] + ' ' + a[n[4][1]]) + 'Hundred ' : '';
    str += (n[5] != 0) ? ((str != '') ? 'and ' : '') + (a[Number(n[5])] || b[n[5][0]] + ' ' + a[n[5][1]]) : '';
    return str ? str.trim() + ' Rupees Only' : 'Zero Rupees Only';
}

function generateVoucherHTML(e) {
    var amt = parseFloat(e.amount || 0);
    var amtWords = numberToWords(Math.round(amt));
    
    var onAccount = (e.expense_category || '') + (e.description ? ' - ' + e.description : '');
    var dateStr = e.expense_date ? e.expense_date.split('-').reverse().join('-') : '';
    
    var proofsHtml = '';
    if (e.proof_file) {
        var files = e.proof_file.split(',');
        files.forEach(function(f) {
            var ext = f.split('.').pop().toLowerCase();
            if (['jpg','jpeg','png','gif','webp'].includes(ext)) {
                proofsHtml += '<img src="'+f+'" />';
            }
        });
    }

    var html = `
    <div class="voucher-page">
        <div class="voucher-header">
            <h2>ABRA Design and Build</h2>
            <h3>Payment Voucher</h3>
        </div>
        <div class="voucher-box">
            <div class="voucher-row" style="justify-content: flex-end;">
                <span class="voucher-label" style="width:50px;">Date:</span>
                <span class="voucher-value" style="width:150px; flex-grow:0;">${escapeHtml(dateStr)}</span>
            </div>
            <div class="voucher-row">
                <span class="voucher-label">Amount (₹):</span>
                <span class="voucher-value">${amt.toLocaleString('en-IN', {minimumFractionDigits:2})}</span>
            </div>
            <div class="voucher-row">
                <span class="voucher-label">Amount in Words:</span>
                <span class="voucher-value">${amtWords}</span>
            </div>
            <div class="voucher-row">
                <span class="voucher-label">Payment Method:</span>
                <span class="voucher-value">UPI</span>
            </div>
            <div class="voucher-row">
                <span class="voucher-label">Amount Paid To:</span>
                <span class="voucher-value"></span>
            </div>
            <div class="voucher-row">
                <span class="voucher-label">On Account of:</span>
                <span class="voucher-value">${escapeHtml(onAccount)}</span>
            </div>
            <div class="voucher-footer">
                <div class="voucher-signature">Authorised By</div>
                <div class="voucher-signature">Received By / Signature</div>
            </div>
        </div>
        ${proofsHtml ? '<div class="voucher-proofs"><h4>Attached Proofs</h4><div class="voucher-proofs-grid">' + proofsHtml + '</div></div>' : ''}
    </div>
    `;
    return html;
}

function printSingleVoucher(id) {
    var e = window.rawExpensesData[id];
    if (!e) return;
    $('#voucher_print_container').html(generateVoucherHTML(e));
    window.print();
}

function toggleAllExpenses(source) {
    $('.chk-expense').prop('checked', source.checked);
    toggleExpenseSelection();
}

function toggleExpenseSelection() {
    var anyChecked = $('.chk-expense:checked').length > 0;
    if (anyChecked) {
        $('#btn_print_selected').show();
    } else {
        $('#btn_print_selected').hide();
    }
}

function printSelectedVouchers() {
    var html = '';
    $('.chk-expense:checked').each(function() {
        var id = $(this).val();
        if (window.rawExpensesData[id]) {
            html += generateVoucherHTML(window.rawExpensesData[id]);
        }
    });
    if (!html) return;
    $('#voucher_print_container').html(html);
    window.print();
}
</script>

<!-- HIDDEN VOUCHER PRINT CONTAINER -->
<div id="voucher_print_container" style="display:none;"></div>
<style>
@media print {
    body > :not(#voucher_print_container) { display: none !important; }
    #voucher_print_container { display: block !important; width: 100%; background: #fff; }
    html, body { background: #fff; margin: 0; padding: 0; height: auto; }
    .voucher-page { font-family: 'Poppins', sans-serif; padding: 30px; margin-bottom: 20px; color: #000; }
    .voucher-page:not(:last-child) { page-break-after: always; }
    .voucher-header { text-align: center; margin-bottom: 30px; }
    .voucher-header h2 { margin: 0; font-size: 24px; font-weight: 700; text-transform: uppercase; }
    .voucher-header h3 { margin: 5px 0 0; font-size: 18px; font-weight: 400; color: #555; }
    .voucher-box { border: 2px solid #333; padding: 30px; border-radius: 8px; }
    .voucher-row { margin-bottom: 25px; font-size: 16px; display: flex; align-items: flex-end; }
    .voucher-label { font-weight: 600; width: 200px; flex-shrink: 0; }
    .voucher-value { flex-grow: 1; border-bottom: 1px dashed #333; padding-bottom: 5px; font-weight: 500; font-style: italic; min-height: 25px; }
    .voucher-footer { display: flex; justify-content: space-between; margin-top: 100px; }
    .voucher-signature { text-align: center; width: 250px; border-top: 1px solid #333; padding-top: 10px; font-weight: 600; }
    .voucher-proofs { margin-top: 40px; text-align: center; }
    .voucher-proofs h4 { margin-bottom: 15px; color: #333; }
    .voucher-proofs-grid { display: flex; flex-wrap: wrap; justify-content: center; gap: 15px; }
    .voucher-proofs-grid img { width: 48%; max-height: 850px; border: 1px solid #ccc; object-fit: contain; border-radius: 4px; box-sizing: border-box; }
    @page { margin: 0.5cm; }
}
</style>
</body>
</html>

