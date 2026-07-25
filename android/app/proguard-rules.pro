# Flutter's own engine/embedding classes are already covered by the
# consumer rules bundled in the Flutter Gradle plugin; the rules below only
# cover this app's own native glue and plugins whose Android side leans on
# reflection or the Keystore/Biometric APIs, which R8 can otherwise strip.

# MainActivity's EventChannel/MethodChannel handlers are wired up in
# configureFlutterEngine and never referenced from Dart by class name, but
# keep the class intact anyway since it's the manifest-declared launcher
# Activity these channels are scoped to.
-keep class com.sbarpanda.expendituretracker.MainActivity { *; }

# flutter_secure_storage (Android Keystore / EncryptedSharedPreferences)
-keep class androidx.security.crypto.** { *; }

# local_auth (BiometricPrompt)
-keep class androidx.biometric.** { *; }

# sqflite's native bridge
-keep class com.tekartik.sqflite.** { *; }

-dontwarn androidx.**
