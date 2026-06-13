import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';
import '../../../../core/finance_secure_storage.dart';
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewDigitalExpensePage extends StatefulWidget {
  final bool showAppBar;
  final Map<String, dynamic>? expenseData;
  final bool isViewOnly;

  const NewDigitalExpensePage({
    Key? key, 
    this.showAppBar = true,
    this.expenseData,
    this.isViewOnly = false,
  }) : super(key: key);

  @override
  State<NewDigitalExpensePage> createState() => _NewDigitalExpensePageState();
}

class _NewDigitalExpensePageState extends State<NewDigitalExpensePage> {
  final _formKey = GlobalKey<FormState>();

  final _dateCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _paymentMethodCtrl = TextEditingController();
  final _amountPaidToCtrl = TextEditingController();
  final _amountInWordsCtrl = TextEditingController();
  final _onAccountOfCtrl = TextEditingController();
  final _receivedByCtrl = TextEditingController();
  
  String? _selectedCategory;

  List<PlatformFile> _receiptFiles = [];
  List<String> _existingProofUrls = [];  // URLs of already-uploaded proofs

  bool _isSaving = false;

  final List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _loadCategories();
    
    if (widget.expenseData != null) {
      final exp = widget.expenseData!;
      if (exp['date'] != null) _dateCtrl.text = exp['date'];
      if (exp['amount'] != null) _amountCtrl.text = exp['amount'].toString();
      if (exp['paymentMethod'] != null) _paymentMethodCtrl.text = exp['paymentMethod'];
      if (exp['amountPaidTo'] != null) _amountPaidToCtrl.text = exp['amountPaidTo'];
      if (exp['amountInWords'] != null) _amountInWordsCtrl.text = exp['amountInWords'];
      if (exp['onAccountOf'] != null) _onAccountOfCtrl.text = exp['onAccountOf'];
      if (exp['receivedBy'] != null) _receivedByCtrl.text = exp['receivedBy'];
      if (exp['expenseCategory'] != null) _selectedCategory = exp['expenseCategory'];
      // Load existing proof image URLs to display
      if (exp['proofFiles'] != null && (exp['proofFiles'] as List).isNotEmpty) {
        for (var p in (exp['proofFiles'] as List)) {
          if (p['path'] != null) _existingProofUrls.add('${ApiConfig.baseUrl}/${p['path']}');
        }
      } else if (exp['proofFile'] != null && exp['proofFile']['path'] != null) {
        _existingProofUrls.add('${ApiConfig.baseUrl}/${exp['proofFile']['path']}');
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/digital-expenses/categories'),
        headers: {
          'Authorization': 'Bearer $token',
          'x-branch-ids': branchHdr,
          'x-org-ids': orgHdr,
        }
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] && mounted) {
          setState(() {
            _categories.clear();
            _categories.addAll(List<String>.from(data['data']));
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }
  
  Future<void> _saveCategoryToDb(String categoryName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/digital-expenses/categories'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'x-branch-ids': branchHdr,
          'x-org-ids': orgHdr,
        },
        body: json.encode({'categoryName': categoryName})
      );
    } catch (e) {
      debugPrint('Error saving category: $e');
    }
  }

  String _numberToWords(num number) {
    if (number == 0) return 'Zero';
    const units = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
    
    String convertWhole(int n) {
      if (n < 20) return units[n];
      if (n < 100) return tens[n ~/ 10] + (n % 10 != 0 ? ' ${units[n % 10]}' : '');
      if (n < 1000) return '${units[n ~/ 100]} Hundred' + (n % 100 != 0 ? ' and ${convertWhole(n % 100)}' : '');
      if (n < 100000) return '${convertWhole(n ~/ 1000)} Thousand' + (n % 1000 != 0 ? ' ${convertWhole(n % 1000)}' : '');
      if (n < 10000000) return '${convertWhole(n ~/ 100000)} Lakh' + (n % 100000 != 0 ? ' ${convertWhole(n % 100000)}' : '');
      return '${convertWhole(n ~/ 10000000)} Crore' + (n % 10000000 != 0 ? ' ${convertWhole(n % 10000000)}' : '');
    }

    int wholePart = number.toInt();
    int decimalPart = ((number - wholePart) * 100).round();
    
    String words = '${convertWhole(wholePart)} Rupees';
    if (decimalPart > 0) {
      words += ' and ${convertWhole(decimalPart)} Paise';
    }
    return '$words Only';
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _amountCtrl.dispose();
    _paymentMethodCtrl.dispose();
    _amountPaidToCtrl.dispose();
    _amountInWordsCtrl.dispose();
    _onAccountOfCtrl.dispose();
    _receivedByCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf'],
        withData: kIsWeb,
        allowMultiple: true,
      );
      if (result != null) {
        setState(() {
          _receiptFiles.addAll(result.files);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an Expense Category'), backgroundColor: Colors.red));
      return;
    }
    
    setState(() => _isSaving = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      final isEditing = widget.expenseData != null && widget.expenseData!['_id'] != null;
      final uri = isEditing 
          ? Uri.parse('${ApiConfig.baseUrl}/api/finance/digital-expenses/${widget.expenseData!['_id']}')
          : Uri.parse('${ApiConfig.baseUrl}/api/finance/digital-expenses');
          
      var request = http.MultipartRequest(isEditing ? 'PUT' : 'POST', uri);
      
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['x-branch-ids'] = branchHdr;
      request.headers['x-org-ids'] = orgHdr;

      request.fields['date'] = _dateCtrl.text;
      request.fields['amount'] = _amountCtrl.text;
      request.fields['paymentMethod'] = _paymentMethodCtrl.text;
      request.fields['amountPaidTo'] = _amountPaidToCtrl.text;
      request.fields['amountInWords'] = _amountInWordsCtrl.text;
      request.fields['onAccountOf'] = _onAccountOfCtrl.text;
      request.fields['expenseCategory'] = _selectedCategory!;
      request.fields['receivedBy'] = _receivedByCtrl.text;
      
      // Explicitly set status to Pending so that editing a Declined voucher resubmits it for approval
      request.fields['status'] = 'Pending';

      for (var file in _receiptFiles) {
        if (kIsWeb && file.bytes != null) {
          request.files.add(http.MultipartFile.fromBytes('proofFiles', file.bytes!, filename: file.name));
        } else if (file.path != null) {
          request.files.add(await http.MultipartFile.fromPath('proofFiles', file.path!));
        }
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      var result = json.decode(response.body);

      if (response.statusCode == 200 && result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Digital expense submitted successfully!'), backgroundColor: Colors.green));
        if (mounted) Navigator.pop(context, true);
      } else {
        throw Exception(result['message'] ?? 'Failed to submit');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildFieldRow(String label, TextEditingController ctrl, {bool isNumber = false, int maxLines = 1, bool readOnly = false, String? hint, Function(String)? onChanged, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrl,
            readOnly: readOnly || widget.isViewOnly || onTap != null,
            onTap: onTap,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            maxLines: maxLines,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navyMid)),
              filled: true,
              fillColor: (readOnly || widget.isViewOnly) ? Colors.grey.shade50 : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.isViewOnly)
          GestureDetector(
            onTap: _pickReceipt,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Icon(Icons.camera_alt_outlined, size: 32, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('Upload Proof / Camera Capture', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text('Drag and drop or click here (Supports Multiple)', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        if (_receiptFiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _receiptFiles.map((file) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade100,
                    ),
                    child: file.bytes != null && (file.extension == 'jpg' || file.extension == 'png' || file.extension == 'jpeg')
                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(file.bytes!, fit: BoxFit.cover))
                      : const Center(child: Icon(Icons.insert_drive_file, color: Colors.grey, size: 30)),
                  ),
                  if (!widget.isViewOnly)
                    Positioned(
                      top: -8, right: -8,
                      child: InkWell(
                        onTap: () => setState(() => _receiptFiles.remove(file)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                ],
              );
            }).toList(),
          ),
        ],
        // ── Already-uploaded proofs from server ──
        if (_existingProofUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.cloud_done, color: Colors.green, size: 16),
            const SizedBox(width: 6),
            Text('Already Uploaded (${_existingProofUrls.length})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.green)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _existingProofUrls.map((url) {
              return Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green.shade300, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.insert_drive_file, color: Colors.grey, size: 30)),
                        loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.8), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(7), bottomRight: Radius.circular(7))),
                        child: const Text('Saved', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ]
      ],
    );
  }

  // ==========================================================================
  // UI HELPERS
  // ==========================================================================
  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))
      ]
    ),
    child: child,
  );

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
        borderRadius: BorderRadius.circular(6)
      ),
      child: Icon(icon, color: Colors.white, size: 18)
    ),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
  ]);

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_navyDark, _navyMid, _navyLight], begin: Alignment.centerLeft, end: Alignment.centerRight),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('New Payment Voucher', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              label: const Text('Cancel', style: TextStyle(color: Colors.white70))
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Submit Voucher'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.showAppBar)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Payment Voucher', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _navyDark)),
                IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showAppBar) ...[
                _sectionTitle('Payment Voucher', Icons.receipt_long),
                const SizedBox(height: 24),
              ],
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildFieldRow('Date (YYYY-MM-DD)', _dateCtrl, onTap: () async {
                      if (widget.isViewOnly) return;
                      final initialDate = DateTime.tryParse(_dateCtrl.text) ?? DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initialDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                        });
                      }
                    })
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Expense Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black54)),
                        const SizedBox(height: 8),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            final query = textEditingValue.text.toLowerCase();
                            final matches = _categories.where((cat) => cat.toLowerCase().contains(query)).toList();
                            return matches.isEmpty && query.isNotEmpty ? [textEditingValue.text] : matches;
                          },
                          onSelected: (String selection) {
                            setState(() {
                              if (!_categories.contains(selection)) {
                                _categories.add(selection);
                                _saveCategoryToDb(selection);
                              }
                              _selectedCategory = selection;
                            });
                          },
                          fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                            if (_selectedCategory != null && controller.text.isEmpty) {
                              controller.text = _selectedCategory!;
                            }
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              onEditingComplete: onEditingComplete,
                              onChanged: (v) {
                                if (v.isEmpty) setState(() => _selectedCategory = null);
                              },
                              decoration: InputDecoration(
                                hintText: "Search or type new category...",
                                filled: true,
                                fillColor: widget.isViewOnly ? Colors.grey.shade50 : Colors.white,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[400]!)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[400]!)),
                                prefixIcon: const Icon(Icons.category, color: _navyAccent),
                                suffixIcon: _selectedCategory == null && controller.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.add_circle, color: _navyAccent),
                                        tooltip: 'Add new category',
                                        onPressed: () {
                                          final newCat = controller.text.trim();
                                          if (newCat.isNotEmpty) {
                                            setState(() {
                                              if (!_categories.contains(newCat)) {
                                                _categories.add(newCat);
                                                _saveCategoryToDb(newCat);
                                              }
                                              _selectedCategory = newCat;
                                              FocusScope.of(context).unfocus();
                                            });
                                          }
                                        },
                                      )
                                    : const Icon(Icons.arrow_drop_down, color: Colors.grey),
                              ),
                              readOnly: widget.isViewOnly,
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4.0,
                                borderRadius: BorderRadius.circular(8),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 250, maxWidth: 350),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      final String option = options.elementAt(index);
                                      final isNew = !_categories.contains(option);
                                      return ListTile(
                                        leading: Icon(isNew ? Icons.add : Icons.category, color: _navyAccent),
                                        title: Text(isNew ? "Add '$option'" : option, style: TextStyle(fontWeight: isNew ? FontWeight.bold : FontWeight.normal)),
                                        onTap: () => onSelected(option),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    )
                  )
                ],
              ),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildFieldRow('Amount (₹) *', _amountCtrl, isNumber: true, onChanged: (v) {
                    setState(() {
                      final val = double.tryParse(v);
                      if (val != null) {
                        _amountInWordsCtrl.text = _numberToWords(val);
                      } else {
                        _amountInWordsCtrl.text = '';
                      }
                    });
                  })),
                  const SizedBox(width: 16),
                  Expanded(child: _buildFieldRow('Payment Method', _paymentMethodCtrl)),
                ],
              ),

              _buildFieldRow('Amount Paid To', _amountPaidToCtrl),
              _buildFieldRow('Amount in Words', _amountInWordsCtrl),
              _buildFieldRow('On Account of (Description)', _onAccountOfCtrl, maxLines: 2),
              _buildFieldRow('Received By', _receivedByCtrl),
            ]
          )
        ),
        const SizedBox(height: 20),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Proof / Attachment', Icons.attach_file),
              const SizedBox(height: 16),
              _buildAttachmentZone(),
            ]
          )
        )
      ],
    );
  }

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!)
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Amount', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  Text('₹${_amountCtrl.text.isEmpty ? '0.00' : _amountCtrl.text}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navyDark)),
                ],
              )
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
            label: Text(_isSaving ? 'Submitting...' : 'Submit Voucher'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
            ),
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: _buildMainContent())),
                  Container(
                    width: 340,
                    color: Colors.white,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildSummarySection(),
                    ),
                  ),
                ],
              );
            } else {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(padding: const EdgeInsets.all(20), child: _buildMainContent()),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(20),
                      child: _buildSummarySection(),
                    ),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
