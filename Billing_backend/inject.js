const fs = require('fs');
const base64 = fs.readFileSync('d:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_backend/sig_base64.txt', 'utf8').trim();
const file = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/digital-expenses-finance-suite.php';
let content = fs.readFileSync(file, 'utf8');
const target = `<div class="v-sig-block" style="color:<?php echo $isApproved ? '#059669' : '#c2410c'; ?>;"><?php echo $isApproved ? 'Approved Digitally' : 'Pending Approval'; ?><br><span style="font-weight:400;color:#64748b;">Manager Approval</span></div>`;
const repl = `<div class="v-sig-block" style="text-align: center; color:<?php echo $isApproved ? '#059669' : '#c2410c'; ?>;">
    <?php if($isApproved): ?>
        <img src="${base64}" style="height: 50px; display: block; margin: 0 auto 5px auto;" alt="Digital Signature">
    <?php endif; ?>
    <?php echo $isApproved ? 'Approved Digitally' : 'Pending Approval'; ?><br>
    <span style="font-weight:400;color:#64748b;">Manager Approval</span>
</div>`;
content = content.replace(target, repl);
fs.writeFileSync(file, content);
console.log('Injected successfully');
