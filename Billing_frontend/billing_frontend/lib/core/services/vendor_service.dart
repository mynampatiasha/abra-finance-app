import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class VendorService {
  static String get baseUrl => '${ApiConfig.baseUrl}/api/admin';
  
  // Get authentication token
  Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      print('Error getting auth token: $e');
      return null;
    }
  }

  // Get headers with authentication
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Get all vendors
  Future<Map<String, dynamic>> getVendors({String? search}) async {
    try {
      final headers = await _getHeaders();
      
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      
      final uri = Uri.parse('$baseUrl/vendors').replace(queryParameters: queryParams);
      
      print('📡 Fetching vendors from: $uri');
      
      final response = await http.get(uri, headers: headers);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data['data'] ?? [],
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to fetch vendors',
        };
      }
    } catch (e) {
      print('❌ Error fetching vendors: $e');
      return {
        'success': false,
        'message': 'Error fetching vendors: $e',
      };
    }
  }

  /// Create a new vendor
  Future<Map<String, dynamic>> createVendor({
    required String name,
    required String email,
    required String phone,
    required String location,
    List<String>? vehicles,
  }) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/vendors');
      
      final body = {
        'name': name,
        'email': email,
        'phone': phone,
        'location': location,
        'vehicles': vehicles ?? [],
      };
      
      print('📡 Creating vendor: $uri');
      print('📤 Request body: ${json.encode(body)}');
      
      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode(body),
      );
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'] ?? 'Vendor created successfully',
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to create vendor',
        };
      }
    } catch (e) {
      print('❌ Error creating vendor: $e');
      return {
        'success': false,
        'message': 'Error creating vendor: $e',
      };
    }
  }

  /// Update an existing vendor
  Future<Map<String, dynamic>> updateVendor({
    required String vendorId,
    String? name,
    String? email,
    String? phone,
    String? location,
    List<String>? vehicles,
  }) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/vendors/$vendorId');
      
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (email != null) body['email'] = email;
      if (phone != null) body['phone'] = phone;
      if (location != null) body['location'] = location;
      if (vehicles != null) body['vehicles'] = vehicles;
      
      print('📡 Updating vendor: $uri');
      
      final response = await http.put(
        uri,
        headers: headers,
        body: json.encode(body),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'] ?? 'Vendor updated successfully',
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to update vendor',
        };
      }
    } catch (e) {
      print('❌ Error updating vendor: $e');
      return {
        'success': false,
        'message': 'Error updating vendor: $e',
      };
    }
  }

  /// Delete a vendor
  Future<Map<String, dynamic>> deleteVendor(String vendorId) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/vendors/$vendorId');
      
      print('📡 Deleting vendor: $uri');
      
      final response = await http.delete(uri, headers: headers);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Vendor deleted successfully',
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to delete vendor',
        };
      }
    } catch (e) {
      print('❌ Error deleting vendor: $e');
      return {
        'success': false,
        'message': 'Error deleting vendor: $e',
      };
    }
  }

  /// Add vehicle to vendor
  Future<Map<String, dynamic>> addVehicleToVendor({
    required String vendorId,
    required String vehicleNumber,
  }) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/vendors/$vendorId/vehicles');
      
      final body = {'vehicleNumber': vehicleNumber};
      
      print('📡 Adding vehicle to vendor: $uri');
      
      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode(body),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'] ?? 'Vehicle added successfully',
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to add vehicle',
        };
      }
    } catch (e) {
      print('❌ Error adding vehicle: $e');
      return {
        'success': false,
        'message': 'Error adding vehicle: $e',
      };
    }
  }

  /// Remove vehicle from vendor
  Future<Map<String, dynamic>> removeVehicleFromVendor({
    required String vendorId,
    required String vehicleNumber,
  }) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/vendors/$vendorId/vehicles/$vehicleNumber');
      
      print('📡 Removing vehicle from vendor: $uri');
      
      final response = await http.delete(uri, headers: headers);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'] ?? 'Vehicle removed successfully',
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to remove vehicle',
        };
      }
    } catch (e) {
      print('❌ Error removing vehicle: $e');
      return {
        'success': false,
        'message': 'Error removing vehicle: $e',
      };
    }
  }
}