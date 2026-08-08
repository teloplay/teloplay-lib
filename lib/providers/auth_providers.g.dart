// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(authService)
final authServiceProvider = AuthServiceProvider._();

final class AuthServiceProvider
    extends $FunctionalProvider<AuthService, AuthService, AuthService>
    with $Provider<AuthService> {
  AuthServiceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'authServiceProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$authServiceHash();

  @$internal
  @override
  $ProviderElement<AuthService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthService create(Ref ref) {
    return authService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthService>(value),
    );
  }
}

String _$authServiceHash() => r'1a086f396b6916ee8c5a9a14df3ece637f134805';

/// বর্তমান auth state (login/logout/token-refresh ইত্যাদি) — এটা watch করে
/// Welcome screen বনাম Home screen-এর মধ্যে navigate করা হবে।

@ProviderFor(authStateChanges)
final authStateChangesProvider = AuthStateChangesProvider._();

/// বর্তমান auth state (login/logout/token-refresh ইত্যাদি) — এটা watch করে
/// Welcome screen বনাম Home screen-এর মধ্যে navigate করা হবে।

final class AuthStateChangesProvider extends $FunctionalProvider<
        AsyncValue<AuthState>, AuthState, Stream<AuthState>>
    with $FutureModifier<AuthState>, $StreamProvider<AuthState> {
  /// বর্তমান auth state (login/logout/token-refresh ইত্যাদি) — এটা watch করে
  /// Welcome screen বনাম Home screen-এর মধ্যে navigate করা হবে।
  AuthStateChangesProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'authStateChangesProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$authStateChangesHash();

  @$internal
  @override
  $StreamProviderElement<AuthState> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<AuthState> create(Ref ref) {
    return authStateChanges(ref);
  }
}

String _$authStateChangesHash() => r'592155ed023c2ef5efae28d90345ef8a39466b21';

/// সুবিধার জন্য — বর্তমান user guest কিনা সরাসরি জানার provider

@ProviderFor(isGuestUser)
final isGuestUserProvider = IsGuestUserProvider._();

/// সুবিধার জন্য — বর্তমান user guest কিনা সরাসরি জানার provider

final class IsGuestUserProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// সুবিধার জন্য — বর্তমান user guest কিনা সরাসরি জানার provider
  IsGuestUserProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'isGuestUserProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$isGuestUserHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return isGuestUser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isGuestUserHash() => r'721b10bfffc5ff1655811eeb93403d6f164b1188';
