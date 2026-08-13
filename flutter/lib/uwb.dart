import 'package:flutter/services.dart';

/// Detecção do hardware UWB (chip de banda ultralarga, Android 12+).
///
/// O ranging real (distância em cm + azimute) exige um par FiRa cooperando
/// do outro lado — a UI usa esta detecção para anunciar o modo precisão nos
/// aparelhos capazes; a sessão de ranging entra quando houver acessório
/// compatível para testar.
class Uwb {
  static const _channel = MethodChannel('sonda/uwb');
  static bool? _supported;

  static Future<bool> isSupported() async {
    if (_supported != null) return _supported!;
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      _supported = false;
    }
    return _supported!;
  }
}
