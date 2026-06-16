import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ko')];

  /// Application / brand name shown in app bars and the splash screen.
  ///
  /// In ko, this message translates to:
  /// **'HelpBee'**
  String get appName;

  /// No description provided for @splashTagline.
  ///
  /// In ko, this message translates to:
  /// **'사진 한 장으로 응애 진단'**
  String get splashTagline;

  /// No description provided for @onbTitle1.
  ///
  /// In ko, this message translates to:
  /// **'벌 사진 한 장으로 응애 감염 위험을 진단해요'**
  String get onbTitle1;

  /// No description provided for @onbBody1.
  ///
  /// In ko, this message translates to:
  /// **'최첨단 AI가 벌의 상태를 분석하여 응애 감염 여부를 즉시 확인해 드립니다'**
  String get onbBody1;

  /// No description provided for @onbTitle2.
  ///
  /// In ko, this message translates to:
  /// **'가이드 안에 벌통을 맞추고 찍기만 하면 돼요'**
  String get onbTitle2;

  /// No description provided for @onbBody2.
  ///
  /// In ko, this message translates to:
  /// **'장갑을 낀 상태에서도 편리하게 자동 초점 가이드로 정확하게 촬영하세요'**
  String get onbBody2;

  /// No description provided for @onbTitle3.
  ///
  /// In ko, this message translates to:
  /// **'분석이 끝나면 알림으로 알려 드릴게요'**
  String get onbTitle3;

  /// No description provided for @onbBody3.
  ///
  /// In ko, this message translates to:
  /// **'현장에서 바쁜 작업을 하시는 동안 HelpBee가 꼼꼼히 분석해 드립니다'**
  String get onbBody3;

  /// No description provided for @onbSkip.
  ///
  /// In ko, this message translates to:
  /// **'건너뛰기'**
  String get onbSkip;

  /// No description provided for @onbNext.
  ///
  /// In ko, this message translates to:
  /// **'다음 단계로'**
  String get onbNext;

  /// No description provided for @onbStart.
  ///
  /// In ko, this message translates to:
  /// **'시작하기'**
  String get onbStart;

  /// No description provided for @emailLabel.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get emailLabel;

  /// No description provided for @emailHint.
  ///
  /// In ko, this message translates to:
  /// **'이메일 주소를 입력하세요'**
  String get emailHint;

  /// No description provided for @passwordLabel.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호'**
  String get passwordLabel;

  /// No description provided for @passwordHint.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 입력하세요'**
  String get passwordHint;

  /// No description provided for @keepLoggedIn.
  ///
  /// In ko, this message translates to:
  /// **'로그인 상태 유지'**
  String get keepLoggedIn;

  /// No description provided for @loginCta.
  ///
  /// In ko, this message translates to:
  /// **'로그인하기'**
  String get loginCta;

  /// No description provided for @findId.
  ///
  /// In ko, this message translates to:
  /// **'아이디 찾기'**
  String get findId;

  /// No description provided for @findPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 찾기'**
  String get findPassword;

  /// No description provided for @signupLink.
  ///
  /// In ko, this message translates to:
  /// **'회원가입'**
  String get signupLink;

  /// No description provided for @snsDivider.
  ///
  /// In ko, this message translates to:
  /// **'SNS 계정으로 로그인하기'**
  String get snsDivider;

  /// No description provided for @comingSoon.
  ///
  /// In ko, this message translates to:
  /// **'준비 중입니다'**
  String get comingSoon;

  /// No description provided for @signupTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원가입'**
  String get signupTitle;

  /// No description provided for @nameLabel.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get nameLabel;

  /// No description provided for @nameHint.
  ///
  /// In ko, this message translates to:
  /// **'이름을 입력하세요'**
  String get nameHint;

  /// No description provided for @passwordRuleHint.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 10자 이상이에요'**
  String get passwordRuleHint;

  /// No description provided for @passwordConfirmLabel.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 확인'**
  String get passwordConfirmLabel;

  /// No description provided for @passwordConfirmHint.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 다시 입력하세요'**
  String get passwordConfirmHint;

  /// No description provided for @passwordMismatch.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 일치하지 않습니다'**
  String get passwordMismatch;

  /// No description provided for @signupCta.
  ///
  /// In ko, this message translates to:
  /// **'가입하기'**
  String get signupCta;

  /// No description provided for @haveAccount.
  ///
  /// In ko, this message translates to:
  /// **'이미 계정이 있으신가요?'**
  String get haveAccount;

  /// No description provided for @goLogin.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get goLogin;

  /// No description provided for @homeTitle.
  ///
  /// In ko, this message translates to:
  /// **'양봉장 현황'**
  String get homeTitle;

  /// No description provided for @homePlaceholderBody.
  ///
  /// In ko, this message translates to:
  /// **'로그인 완료! 홈 화면은 다음 단계에서 만들어집니다.'**
  String get homePlaceholderBody;

  /// No description provided for @logout.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get logout;

  /// No description provided for @valEmail.
  ///
  /// In ko, this message translates to:
  /// **'올바른 이메일 형식이 아니에요'**
  String get valEmail;

  /// No description provided for @valRequired.
  ///
  /// In ko, this message translates to:
  /// **'필수 입력 항목이에요'**
  String get valRequired;

  /// No description provided for @valPasswordLen.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 10자 이상이어야 해요'**
  String get valPasswordLen;

  /// No description provided for @errInvalidCredentials.
  ///
  /// In ko, this message translates to:
  /// **'이메일 또는 비밀번호가 올바르지 않아요'**
  String get errInvalidCredentials;

  /// No description provided for @errAccountLocked.
  ///
  /// In ko, this message translates to:
  /// **'로그인 시도가 많아 잠시 잠겼어요. 잠시 후 다시 시도해 주세요'**
  String get errAccountLocked;

  /// No description provided for @errEmailTaken.
  ///
  /// In ko, this message translates to:
  /// **'이미 가입된 이메일이에요'**
  String get errEmailTaken;

  /// No description provided for @errEmailNotVerified.
  ///
  /// In ko, this message translates to:
  /// **'이메일 인증이 필요해요'**
  String get errEmailNotVerified;

  /// No description provided for @errRateLimited.
  ///
  /// In ko, this message translates to:
  /// **'요청이 많아요. 잠시 후 다시 시도해 주세요'**
  String get errRateLimited;

  /// No description provided for @errNetwork.
  ///
  /// In ko, this message translates to:
  /// **'인터넷 연결이 약해요. 잠시 후 다시 시도해 주세요'**
  String get errNetwork;

  /// No description provided for @errTimeout.
  ///
  /// In ko, this message translates to:
  /// **'응답이 지연되고 있어요. 다시 시도해 주세요'**
  String get errTimeout;

  /// No description provided for @errServer.
  ///
  /// In ko, this message translates to:
  /// **'일시적인 오류가 발생했어요'**
  String get errServer;

  /// No description provided for @errValidation.
  ///
  /// In ko, this message translates to:
  /// **'입력한 정보를 다시 확인해 주세요'**
  String get errValidation;

  /// Shown for 429 lockout / rate-limit using the server Retry-After seconds.
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초 후 다시 시도해 주세요'**
  String errRetryAfter(int seconds);

  /// No description provided for @errUnknown.
  ///
  /// In ko, this message translates to:
  /// **'알 수 없는 오류가 발생했어요'**
  String get errUnknown;

  /// No description provided for @showPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 표시'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 숨기기'**
  String get hidePassword;

  /// No description provided for @commonRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get commonConfirm;

  /// No description provided for @back.
  ///
  /// In ko, this message translates to:
  /// **'뒤로'**
  String get back;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
