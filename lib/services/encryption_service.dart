import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  static final _key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1');

  // We no longer define a static IV here.

  static String encryptText(String plainText) {
    // Create a new, random IV for each message.
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));

    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // Package the IV and the encrypted data together in a single JSON string.
    final packagedData = {
      'iv': base64Encode(iv.bytes),
      'data': encrypted.base64,
    };
    return jsonEncode(packagedData);
  }

  static String decryptText(String packagedText) {
    // Unpack the JSON string to get the IV and the data.
    final packagedData = jsonDecode(packagedText) as Map<String, dynamic>;
    final iv = encrypt.IV.fromBase64(packagedData['iv'] as String);
    final encrypted = encrypt.Encrypted.fromBase64(packagedData['data'] as String);
    
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));

    // Decrypt using the IV that was sent with the message.
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    return decrypted;
  }
}