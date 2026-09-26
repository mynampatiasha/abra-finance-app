const fs = require('fs');

let content = fs.readFileSync('lib/core/services/budget_service.dart', 'utf8');
const imports = \
import 'dart:io';
import 'package:path_provider/path_provider.dart';
\;
content = content.replace('import \\'dart:convert\\';', 'import \\'dart:convert\\';\\n' + imports);
fs.writeFileSync('lib/core/services/budget_service.dart', content);
