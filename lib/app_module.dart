import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/core_module.dart';
import 'package:yhdm/pages/index_module.dart';

final appModule = createModule(
  register: (c) {
    c
      ..module(coreModule)
      ..module(indexModule);
  },
);
