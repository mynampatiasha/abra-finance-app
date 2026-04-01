// ============================================================================
// create_rate_card_service.dart
// Abra Fleet Management - Rate Card Service
// Bridge between Flutter Frontend and Node.js Backend
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import '../../app/config/api_config.dart';

// ============================================================================
// RATE CARD CONFIG
// ============================================================================
class RateCardConfig {
  static const String rateCardEndpoint = '/api/finance/rate-cards';
}

// ============================================================================
// DATA MODELS
// ============================================================================

class OrganizationDetails {
  final String organizationName;
  final String industryType;
  final String contactPersonName;
  final String contactPhone;
  final String contactEmail;
  final String officeAddress;
  final String officeLatLng;
  final int numberOfEmployees;
  final DateTime contractStartDate;
  final DateTime contractEndDate;
  final String contractType;

  OrganizationDetails({
    required this.organizationName,
    required this.industryType,
    required this.contactPersonName,
    required this.contactPhone,
    required this.contactEmail,
    required this.officeAddress,
    this.officeLatLng = '',
    required this.numberOfEmployees,
    required this.contractStartDate,
    required this.contractEndDate,
    required this.contractType,
  });

  Map<String, dynamic> toJson() => {
    'organizationName':  organizationName,
    'industryType':      industryType,
    'contactPersonName': contactPersonName,
    'contactPhone':      contactPhone,
    'contactEmail':      contactEmail,
    'officeAddress':     officeAddress,
    'officeLatLng':      officeLatLng,
    'numberOfEmployees': numberOfEmployees,
    'contractStartDate': contractStartDate.toIso8601String(),
    'contractEndDate':   contractEndDate.toIso8601String(),
    'contractType':      contractType,
  };

  factory OrganizationDetails.fromJson(Map<String, dynamic> json) => OrganizationDetails(
    organizationName:  json['organizationName'] ?? '',
    industryType:      json['industryType'] ?? '',
    contactPersonName: json['contactPersonName'] ?? '',
    contactPhone:      json['contactPhone'] ?? '',
    contactEmail:      json['contactEmail'] ?? '',
    officeAddress:     json['officeAddress'] ?? '',
    officeLatLng:      json['officeLatLng'] ?? '',
    numberOfEmployees: json['numberOfEmployees'] ?? 0,
    contractStartDate: DateTime.tryParse(json['contractStartDate'] ?? '') ?? DateTime.now(),
    contractEndDate:   DateTime.tryParse(json['contractEndDate'] ?? '') ?? DateTime.now(),
    contractType:      json['contractType'] ?? 'Monthly',
  );
}

class RouteShiftDetails {
  final String routeCode;
  final String routeName;
  final String pickupZone;
  final String dropLocation;
  final double distanceKm;
  final String shiftType;
  final String pickupTime;
  final String dropTime;
  final int tripsPerDay;
  final String daysOfOperation;
  final bool serviceOnHolidays;

  RouteShiftDetails({
    required this.routeCode,
    required this.routeName,
    required this.pickupZone,
    required this.dropLocation,
    required this.distanceKm,
    required this.shiftType,
    required this.pickupTime,
    required this.dropTime,
    required this.tripsPerDay,
    required this.daysOfOperation,
    this.serviceOnHolidays = false,
  });

  Map<String, dynamic> toJson() => {
    'routeCode':         routeCode,
    'routeName':         routeName,
    'pickupZone':        pickupZone,
    'dropLocation':      dropLocation,
    'distanceKm':        distanceKm,
    'shiftType':         shiftType,
    'pickupTime':        pickupTime,
    'dropTime':          dropTime,
    'tripsPerDay':       tripsPerDay,
    'daysOfOperation':   daysOfOperation,
    'serviceOnHolidays': serviceOnHolidays,
  };

  factory RouteShiftDetails.fromJson(Map<String, dynamic> json) => RouteShiftDetails(
    routeCode:        json['routeCode'] ?? '',
    routeName:        json['routeName'] ?? '',
    pickupZone:       json['pickupZone'] ?? '',
    dropLocation:     json['dropLocation'] ?? '',
    distanceKm:       (json['distanceKm'] ?? 0).toDouble(),
    shiftType:        json['shiftType'] ?? 'Morning',
    pickupTime:       json['pickupTime'] ?? '',
    dropTime:         json['dropTime'] ?? '',
    tripsPerDay:      json['tripsPerDay'] ?? 1,
    daysOfOperation:  json['daysOfOperation'] ?? 'Mon-Fri',
    serviceOnHolidays:json['serviceOnHolidays'] ?? false,
  );
}

class VehicleDetails {
  final String vehicleType;
  final int seatingCapacity;
  final int numberOfVehicles;
  final String vehicleMode;
  final bool isWomenOnlyVehicle;
  final bool escortRequired;
  final bool gpsEnabled;
  final int maxVehicleAgeYears;
  final String driverAssignment;
  final bool driverBgVerified;

  VehicleDetails({
    required this.vehicleType,
    required this.seatingCapacity,
    required this.numberOfVehicles,
    required this.vehicleMode,
    this.isWomenOnlyVehicle = false,
    this.escortRequired = false,
    this.gpsEnabled = true,
    this.maxVehicleAgeYears = 5,
    required this.driverAssignment,
    this.driverBgVerified = false,
  });

  Map<String, dynamic> toJson() => {
    'vehicleType':        vehicleType,
    'seatingCapacity':    seatingCapacity,
    'numberOfVehicles':   numberOfVehicles,
    'vehicleMode':        vehicleMode,
    'isWomenOnlyVehicle': isWomenOnlyVehicle,
    'escortRequired':     escortRequired,
    'gpsEnabled':         gpsEnabled,
    'maxVehicleAgeYears': maxVehicleAgeYears,
    'driverAssignment':   driverAssignment,
    'driverBgVerified':   driverBgVerified,
  };

  factory VehicleDetails.fromJson(Map<String, dynamic> json) => VehicleDetails(
    vehicleType:        json['vehicleType'] ?? 'Sedan',
    seatingCapacity:    json['seatingCapacity'] ?? 4,
    numberOfVehicles:   json['numberOfVehicles'] ?? 1,
    vehicleMode:        json['vehicleMode'] ?? 'Dedicated',
    isWomenOnlyVehicle: json['isWomenOnlyVehicle'] ?? false,
    escortRequired:     json['escortRequired'] ?? false,
    gpsEnabled:         json['gpsEnabled'] ?? true,
    maxVehicleAgeYears: json['maxVehicleAgeYears'] ?? 5,
    driverAssignment:   json['driverAssignment'] ?? 'Dedicated',
    driverBgVerified:   json['driverBgVerified'] ?? false,
  );
}

class PricingDetails {
  final String billingModel;
  final double monthlyBaseRatePerVehicle;
  final double kmIncludedPerMonth;
  final double perTripRate;
  final double zone1Rate;
  final double zone2Rate;
  final double zone3Rate;
  final double zone4Rate;
  final double extraKmRate;
  final double nightShiftSurcharge;
  final String nightShiftStartTime;
  final double weekendSurchargePercent;
  final double festivalHolidayRatePercent;
  final double driverBataPerDay;
  final bool driverBataIncluded;
  final bool tollChargesIncluded;
  final bool parkingChargesIncluded;
  final bool statePermitIncluded;
  final bool fuelIncluded;
  final bool fuelEscalationLinked;
  final double escortChargePerTrip;
  final double cancellationChargeOrg;
  final bool noShowBillable;
  final double gstPercent;
  final double tdsPercent;

  PricingDetails({
    required this.billingModel,
    this.monthlyBaseRatePerVehicle = 0,
    this.kmIncludedPerMonth = 0,
    this.perTripRate = 0,
    this.zone1Rate = 0,
    this.zone2Rate = 0,
    this.zone3Rate = 0,
    this.zone4Rate = 0,
    this.extraKmRate = 0,
    this.nightShiftSurcharge = 0,
    this.nightShiftStartTime = '22:00',
    this.weekendSurchargePercent = 0,
    this.festivalHolidayRatePercent = 0,
    this.driverBataPerDay = 0,
    this.driverBataIncluded = true,
    this.tollChargesIncluded = false,
    this.parkingChargesIncluded = false,
    this.statePermitIncluded = false,
    this.fuelIncluded = true,
    this.fuelEscalationLinked = false,
    this.escortChargePerTrip = 0,
    this.cancellationChargeOrg = 0,
    this.noShowBillable = false,
    this.gstPercent = 5,
    this.tdsPercent = 1,
  });

  Map<String, dynamic> toJson() => {
    'billingModel':               billingModel,
    'monthlyBaseRatePerVehicle':  monthlyBaseRatePerVehicle,
    'kmIncludedPerMonth':         kmIncludedPerMonth,
    'perTripRate':                perTripRate,
    'zonePricing': {
      'zone1_0_10km':  zone1Rate,
      'zone2_10_20km': zone2Rate,
      'zone3_20_30km': zone3Rate,
      'zone4_30plus':  zone4Rate,
    },
    'extraKmRate':                extraKmRate,
    'nightShiftSurcharge':        nightShiftSurcharge,
    'nightShiftStartTime':        nightShiftStartTime,
    'weekendSurchargePercent':    weekendSurchargePercent,
    'festivalHolidayRatePercent': festivalHolidayRatePercent,
    'driverBataPerDay':           driverBataPerDay,
    'driverBataIncluded':         driverBataIncluded,
    'tollChargesIncluded':        tollChargesIncluded,
    'parkingChargesIncluded':     parkingChargesIncluded,
    'statePermitIncluded':        statePermitIncluded,
    'fuelIncluded':               fuelIncluded,
    'fuelEscalationLinked':       fuelEscalationLinked,
    'escortChargePerTrip':        escortChargePerTrip,
    'cancellationChargeOrg':      cancellationChargeOrg,
    'noShowBillable':             noShowBillable,
    'gstPercent':                 gstPercent,
    'tdsPercent':                 tdsPercent,
  };

  factory PricingDetails.fromJson(Map<String, dynamic> json) => PricingDetails(
    billingModel:               json['billingModel'] ?? 'Dedicated Monthly',
    monthlyBaseRatePerVehicle:  (json['monthlyBaseRatePerVehicle'] ?? 0).toDouble(),
    kmIncludedPerMonth:         (json['kmIncludedPerMonth'] ?? 0).toDouble(),
    perTripRate:                (json['perTripRate'] ?? 0).toDouble(),
    zone1Rate:                  (json['zonePricing']?['zone1_0_10km'] ?? 0).toDouble(),
    zone2Rate:                  (json['zonePricing']?['zone2_10_20km'] ?? 0).toDouble(),
    zone3Rate:                  (json['zonePricing']?['zone3_20_30km'] ?? 0).toDouble(),
    zone4Rate:                  (json['zonePricing']?['zone4_30plus'] ?? 0).toDouble(),
    extraKmRate:                (json['extraKmRate'] ?? 0).toDouble(),
    nightShiftSurcharge:        (json['nightShiftSurcharge'] ?? 0).toDouble(),
    nightShiftStartTime:        json['nightShiftStartTime'] ?? '22:00',
    weekendSurchargePercent:    (json['weekendSurchargePercent'] ?? 0).toDouble(),
    festivalHolidayRatePercent: (json['festivalHolidayRatePercent'] ?? 0).toDouble(),
    driverBataPerDay:           (json['driverBataPerDay'] ?? 0).toDouble(),
    driverBataIncluded:         json['driverBataIncluded'] ?? true,
    tollChargesIncluded:        json['tollChargesIncluded'] ?? false,
    parkingChargesIncluded:     json['parkingChargesIncluded'] ?? false,
    statePermitIncluded:        json['statePermitIncluded'] ?? false,
    fuelIncluded:               json['fuelIncluded'] ?? true,
    fuelEscalationLinked:       json['fuelEscalationLinked'] ?? false,
    escortChargePerTrip:        (json['escortChargePerTrip'] ?? 0).toDouble(),
    cancellationChargeOrg:      (json['cancellationChargeOrg'] ?? 0).toDouble(),
    noShowBillable:             json['noShowBillable'] ?? false,
    gstPercent:                 (json['gstPercent'] ?? 5).toDouble(),
    tdsPercent:                 (json['tdsPercent'] ?? 1).toDouble(),
  );
}

class SLADetails {
  final double onTimePickupGuaranteePercent;
  final int maxDelayAllowedMinutes;
  final double penaltyPerLateTrip;
  final int breakdownResponseMinutes;
  final double penaltyNoReplacement;
  final String escalationContact;
  final bool monthlyMISReport;

  SLADetails({
    this.onTimePickupGuaranteePercent = 97,
    this.maxDelayAllowedMinutes = 10,
    this.penaltyPerLateTrip = 0,
    this.breakdownResponseMinutes = 30,
    this.penaltyNoReplacement = 0,
    this.escalationContact = '',
    this.monthlyMISReport = true,
  });

  Map<String, dynamic> toJson() => {
    'onTimePickupGuaranteePercent': onTimePickupGuaranteePercent,
    'maxDelayAllowedMinutes':       maxDelayAllowedMinutes,
    'penaltyPerLateTrip':           penaltyPerLateTrip,
    'breakdownResponseMinutes':     breakdownResponseMinutes,
    'penaltyNoReplacement':         penaltyNoReplacement,
    'escalationContact':            escalationContact,
    'monthlyMISReport':             monthlyMISReport,
  };

  factory SLADetails.fromJson(Map<String, dynamic> json) => SLADetails(
    onTimePickupGuaranteePercent: (json['onTimePickupGuaranteePercent'] ?? 97).toDouble(),
    maxDelayAllowedMinutes:       json['maxDelayAllowedMinutes'] ?? 10,
    penaltyPerLateTrip:           (json['penaltyPerLateTrip'] ?? 0).toDouble(),
    breakdownResponseMinutes:     json['breakdownResponseMinutes'] ?? 30,
    penaltyNoReplacement:         (json['penaltyNoReplacement'] ?? 0).toDouble(),
    escalationContact:            json['escalationContact'] ?? '',
    monthlyMISReport:             json['monthlyMISReport'] ?? true,
  );
}

class UploadedDocument {
  final String id;
  final String documentName;
  final String documentType;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final DateTime uploadedAt;
  final String uploadedBy;

  // For new uploads (not yet on server)
  final File? localFile;
  final Uint8List? localBytes;

  UploadedDocument({
    this.id = '',
    required this.documentName,
    required this.documentType,
    this.filePath = '',
    required this.fileName,
    this.fileSize = 0,
    this.mimeType = '',
    DateTime? uploadedAt,
    this.uploadedBy = '',
    this.localFile,
    this.localBytes,
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  bool get isLocalFile => localFile != null || localBytes != null;

  factory UploadedDocument.fromJson(Map<String, dynamic> json) => UploadedDocument(
    id:           json['_id'] ?? '',
    documentName: json['documentName'] ?? '',
    documentType: json['documentType'] ?? 'Other',
    filePath:     json['filePath'] ?? '',
    fileName:     json['fileName'] ?? '',
    fileSize:     json['fileSize'] ?? 0,
    mimeType:     json['mimeType'] ?? '',
    uploadedAt:   DateTime.tryParse(json['uploadedAt'] ?? '') ?? DateTime.now(),
    uploadedBy:   json['uploadedBy'] ?? '',
  );

  String get fileSizeDisplay {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isPdf => mimeType == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');
  bool get isImage => mimeType.startsWith('image/');
}

class RateCardModel {
  final String id;
  final String rateCardId;
  final String status;
  final OrganizationDetails organization;
  final RouteShiftDetails routeShift;
  final VehicleDetails vehicle;
  final PricingDetails pricing;
  final SLADetails sla;
  final List<UploadedDocument> documents;
  final String internalNotes;
  final double monthlyEstimate;
  final DateTime createdAt;
  final String createdBy;

  RateCardModel({
    this.id = '',
    this.rateCardId = '',
    this.status = 'Draft',
    required this.organization,
    required this.routeShift,
    required this.vehicle,
    required this.pricing,
    required this.sla,
    this.documents = const [],
    this.internalNotes = '',
    this.monthlyEstimate = 0,
    DateTime? createdAt,
    this.createdBy = '',
  }) : createdAt = createdAt ?? DateTime.now();

  factory RateCardModel.fromJson(Map<String, dynamic> json) => RateCardModel(
    id:              json['_id'] ?? '',
    rateCardId:      json['rateCardId'] ?? '',
    status:          json['status'] ?? 'Draft',
    organization:    OrganizationDetails.fromJson(json['organization'] ?? {}),
    routeShift:      RouteShiftDetails.fromJson(json['routeShift'] ?? {}),
    vehicle:         VehicleDetails.fromJson(json['vehicle'] ?? {}),
    pricing:         PricingDetails.fromJson(json['pricing'] ?? {}),
    sla:             SLADetails.fromJson(json['sla'] ?? {}),
    documents:       (json['documents'] as List<dynamic>? ?? [])
                        .map((d) => UploadedDocument.fromJson(d))
                        .toList(),
    internalNotes:   json['internalNotes'] ?? '',
    monthlyEstimate: (json['monthlyEstimate'] ?? 0).toDouble(),
    createdAt:       DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    createdBy:       json['createdBy'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    '_id':             id,
    'rateCardId':      rateCardId,
    'status':          status,
    'organization':    organization.toJson(),
    'routeShift':      routeShift.toJson(),
    'vehicle':         vehicle.toJson(),
    'pricing':         pricing.toJson(),
    'sla':             sla.toJson(),
    'documents':       documents.map((d) => {
      '_id':          d.id,
      'documentName': d.documentName,
      'documentType': d.documentType,
      'filePath':     d.filePath,
      'fileName':     d.fileName,
      'fileSize':     d.fileSize,
      'mimeType':     d.mimeType,
      'uploadedAt':   d.uploadedAt.toIso8601String(),
      'uploadedBy':   d.uploadedBy,
    }).toList(),
    'internalNotes':   internalNotes,
    'monthlyEstimate': monthlyEstimate,
    'createdAt':       createdAt.toIso8601String(),
    'createdBy':       createdBy,
  };
}

class RateCardListResponse {
  final List<RateCardModel> rateCards;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final Map<String, int> stats;

  RateCardListResponse({
    required this.rateCards,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.stats,
  });
}

class TripCalculationResult {
  final String rateCardId;
  final String billingModel;
  final double baseAmount;
  final double gstAmount;
  final double totalAmount;
  final String breakdown;

  TripCalculationResult({
    required this.rateCardId,
    required this.billingModel,
    required this.baseAmount,
    required this.gstAmount,
    required this.totalAmount,
    required this.breakdown,
  });

  factory TripCalculationResult.fromJson(Map<String, dynamic> json) => TripCalculationResult(
    rateCardId:   json['rateCardId'] ?? '',
    billingModel: json['billingModel'] ?? '',
    baseAmount:   (json['calculation']?['baseAmount'] ?? 0).toDouble(),
    gstAmount:    (json['calculation']?['gstAmount'] ?? 0).toDouble(),
    totalAmount:  (json['calculation']?['totalAmount'] ?? 0).toDouble(),
    breakdown:    json['calculation']?['breakdown'] ?? '',
  );
}

// ============================================================================
// RATE CARD SERVICE
// ============================================================================
class RateCardService {
  // ── Auth Token ──────────────────────────────────────────────────────────────
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  static Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> _multipartHeaders() async {
    final token = await _getToken();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Error Handler ────────────────────────────────────────────────────────────
  static String _extractError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body['error'] ?? body['message'] ?? 'Unknown error occurred';
    } catch (_) {
      return 'Request failed with status: ${response.statusCode}';
    }
  }

  // ── 1. CREATE Rate Card ─────────────────────────────────────────────────────
  static Future<RateCardModel> createRateCard({
    required Map<String, dynamic> rateCardData,
    List<UploadedDocument> documents = const [],
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}');
    final request = http.MultipartRequest('POST', uri);

    // Auth headers
    final headers = await _multipartHeaders();
    request.headers.addAll(headers);

    // Main JSON data
    request.fields['data'] = jsonEncode(rateCardData);

    // Attach documents
    for (int i = 0; i < documents.length; i++) {
      final doc = documents[i];
      request.fields['docName_$i'] = doc.documentName;
      request.fields['docType_$i'] = doc.documentType;

      if (kIsWeb && doc.localBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'documents',
          doc.localBytes!,
          filename: doc.fileName,
          contentType: MediaType.parse(doc.mimeType.isNotEmpty ? doc.mimeType : 'application/octet-stream'),
        ));
      } else if (doc.localFile != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'documents',
          doc.localFile!.path,
          filename: doc.fileName,
          contentType: MediaType.parse(doc.mimeType.isNotEmpty ? doc.mimeType : 'application/octet-stream'),
        ));
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201) {
      final json = jsonDecode(response.body);
      return RateCardModel.fromJson(json['data']);
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── 2. GET All Rate Cards ───────────────────────────────────────────────────
  static Future<RateCardListResponse> getRateCards({
    int page = 1,
    int limit = 20,
    String? status,
    String? billingModel,
    String? vehicleType,
    String? organizationName,
    String? contractType,
    String? industryType,
    String? fromDate,
    String? toDate,
    String? search,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
  }) async {
    final queryParams = <String, String>{
      'page':      page.toString(),
      'limit':     limit.toString(),
      'sortBy':    sortBy,
      'sortOrder': sortOrder,
      if (status != null)           'status': status,
      if (billingModel != null)     'billingModel': billingModel,
      if (vehicleType != null)      'vehicleType': vehicleType,
      if (organizationName != null) 'organizationName': organizationName,
      if (contractType != null)     'contractType': contractType,
      if (industryType != null)     'industryType': industryType,
      if (fromDate != null)         'fromDate': fromDate,
      if (toDate != null)           'toDate': toDate,
      if (search != null)           'search': search,
    };

    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _headers());

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final pagination = json['pagination'] ?? {};
      return RateCardListResponse(
        rateCards: (json['data'] as List).map((d) => RateCardModel.fromJson(d)).toList(),
        total:      pagination['total'] ?? 0,
        page:       pagination['page'] ?? 1,
        limit:      pagination['limit'] ?? 20,
        totalPages: pagination['totalPages'] ?? 1,
        stats: Map<String, int>.from(json['stats'] ?? {}),
      );
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── 3. GET Single Rate Card ─────────────────────────────────────────────────
  static Future<RateCardModel> getRateCard(String id) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/$id');
    final response = await http.get(uri, headers: await _headers());

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return RateCardModel.fromJson(json['data']);
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── 4. UPDATE Rate Card ─────────────────────────────────────────────────────
  static Future<RateCardModel> updateRateCard({
    required String id,
    required Map<String, dynamic> rateCardData,
    List<UploadedDocument> newDocuments = const [],
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/$id');
    final request = http.MultipartRequest('PUT', uri);

    final headers = await _multipartHeaders();
    request.headers.addAll(headers);
    request.fields['data'] = jsonEncode(rateCardData);

    for (int i = 0; i < newDocuments.length; i++) {
      final doc = newDocuments[i];
      request.fields['docName_$i'] = doc.documentName;
      request.fields['docType_$i'] = doc.documentType;
      if (kIsWeb && doc.localBytes != null) {
        request.files.add(http.MultipartFile.fromBytes('documents', doc.localBytes!, filename: doc.fileName));
      } else if (doc.localFile != null) {
        request.files.add(await http.MultipartFile.fromPath('documents', doc.localFile!.path, filename: doc.fileName));
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return RateCardModel.fromJson(json['data']);
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── 5. UPDATE Status ────────────────────────────────────────────────────────
  static Future<RateCardModel> updateStatus(String id, String status, {String? approvedBy}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/$id/status');
    final response = await http.patch(
      uri,
      headers: await _headers(),
      body: jsonEncode({'status': status, if (approvedBy != null) 'approvedBy': approvedBy}),
    );
    if (response.statusCode == 200) {
      return RateCardModel.fromJson(jsonDecode(response.body)['data']);
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── 6. DELETE Rate Card ─────────────────────────────────────────────────────
  static Future<void> deleteRateCard(String id) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/$id');
    final response = await http.delete(uri, headers: await _headers());
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  // ── 7. DELETE Document ──────────────────────────────────────────────────────
  static Future<void> deleteDocument(String rateCardId, String docId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/$rateCardId/document/$docId');
    final response = await http.delete(uri, headers: await _headers());
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  // ── 8. CALCULATE TRIP AMOUNT ────────────────────────────────────────────────
  static Future<TripCalculationResult> calculateTripAmount({
    required String rateCardId,
    required double actualKm,
    bool isNightTrip = false,
    bool isWeekend = false,
    bool isFestival = false,
    bool isEmployeeNoShow = false,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/$rateCardId/calculate-trip');
    final response = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({
        'actualKm':         actualKm,
        'isNightTrip':      isNightTrip,
        'isWeekend':        isWeekend,
        'isFestival':       isFestival,
        'isEmployeeNoShow': isEmployeeNoShow,
      }),
    );
    if (response.statusCode == 200) {
      return TripCalculationResult.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── 9. EXPORT CSV ───────────────────────────────────────────────────────────
  static Future<List<int>> exportCsv() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/export/csv');
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode == 200) return response.bodyBytes;
    throw Exception(_extractError(response));
  }

  // ── 10. IMPORT CSV ──────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> importCsv(File csvFile) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/import/csv');
    final request = http.MultipartRequest('POST', uri);
    final headers = await _multipartHeaders();
    request.headers.addAll(headers);
    request.files.add(await http.MultipartFile.fromPath('csvFile', csvFile.path, filename: 'import.csv'));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(_extractError(response));
  }

  // ── 11. GET DOCUMENT URL ────────────────────────────────────────────────────
  static String getDocumentUrl(String rateCardId, String docId, {bool download = false}) {
    return '${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/$rateCardId/document/$docId/view'
        '${download ? '?download=true' : ''}';
  }

  // ── 12. GET STATS ───────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getStats() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${RateCardConfig.rateCardEndpoint}/stats/summary');
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode == 200) return jsonDecode(response.body)['stats'];
    throw Exception(_extractError(response));
  }
}