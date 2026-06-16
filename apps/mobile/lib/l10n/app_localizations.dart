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

  /// No description provided for @commonDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get commonSave;

  /// No description provided for @back.
  ///
  /// In ko, this message translates to:
  /// **'뒤로'**
  String get back;

  /// Home app bar greeting using the signed-in user's name.
  ///
  /// In ko, this message translates to:
  /// **'{name}님, 안녕하세요'**
  String homeGreeting(String name);

  /// No description provided for @navHives.
  ///
  /// In ko, this message translates to:
  /// **'벌통'**
  String get navHives;

  /// No description provided for @navHistory.
  ///
  /// In ko, this message translates to:
  /// **'진단 이력'**
  String get navHistory;

  /// No description provided for @navSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get navSettings;

  /// No description provided for @addHive.
  ///
  /// In ko, this message translates to:
  /// **'벌통 등록'**
  String get addHive;

  /// No description provided for @createHive.
  ///
  /// In ko, this message translates to:
  /// **'등록하기'**
  String get createHive;

  /// No description provided for @hivesEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'등록된 벌통이 없어요'**
  String get hivesEmptyTitle;

  /// No description provided for @hivesEmptyBody.
  ///
  /// In ko, this message translates to:
  /// **'아래 버튼으로 첫 벌통을 등록해 보세요'**
  String get hivesEmptyBody;

  /// No description provided for @hivesErrorTitle.
  ///
  /// In ko, this message translates to:
  /// **'벌통을 불러오지 못했어요'**
  String get hivesErrorTitle;

  /// No description provided for @hiveNameLabel.
  ///
  /// In ko, this message translates to:
  /// **'벌통 이름'**
  String get hiveNameLabel;

  /// No description provided for @hiveNameHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 1번 벌통'**
  String get hiveNameHint;

  /// No description provided for @hiveAddressLabel.
  ///
  /// In ko, this message translates to:
  /// **'주소 (선택)'**
  String get hiveAddressLabel;

  /// No description provided for @hiveAddressHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 경기도 양평군'**
  String get hiveAddressHint;

  /// No description provided for @hiveNoteLabel.
  ///
  /// In ko, this message translates to:
  /// **'메모 (선택)'**
  String get hiveNoteLabel;

  /// No description provided for @hiveNoteHint.
  ///
  /// In ko, this message translates to:
  /// **'특이사항을 적어 두세요'**
  String get hiveNoteHint;

  /// No description provided for @hiveCreated.
  ///
  /// In ko, this message translates to:
  /// **'벌통을 등록했어요'**
  String get hiveCreated;

  /// No description provided for @hiveDeleted.
  ///
  /// In ko, this message translates to:
  /// **'벌통을 삭제했어요'**
  String get hiveDeleted;

  /// No description provided for @deleteHive.
  ///
  /// In ko, this message translates to:
  /// **'벌통 삭제'**
  String get deleteHive;

  /// No description provided for @deleteHiveConfirm.
  ///
  /// In ko, this message translates to:
  /// **'이 벌통을 삭제할까요? 삭제하면 목록에서 사라져요.'**
  String get deleteHiveConfirm;

  /// No description provided for @hiveDetailTitle.
  ///
  /// In ko, this message translates to:
  /// **'벌통 정보'**
  String get hiveDetailTitle;

  /// No description provided for @hiveRiskSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'현재 감염 심각 수준'**
  String get hiveRiskSubtitle;

  /// No description provided for @hiveLocationCard.
  ///
  /// In ko, this message translates to:
  /// **'벌통 위치'**
  String get hiveLocationCard;

  /// No description provided for @installDateLabel.
  ///
  /// In ko, this message translates to:
  /// **'설치날짜'**
  String get installDateLabel;

  /// No description provided for @statusLabel.
  ///
  /// In ko, this message translates to:
  /// **'상태'**
  String get statusLabel;

  /// No description provided for @memoTitle.
  ///
  /// In ko, this message translates to:
  /// **'메모'**
  String get memoTitle;

  /// No description provided for @historyRecentTitle.
  ///
  /// In ko, this message translates to:
  /// **'과거 진단 이력 (최신순)'**
  String get historyRecentTitle;

  /// No description provided for @seeMore.
  ///
  /// In ko, this message translates to:
  /// **'더보기'**
  String get seeMore;

  /// No description provided for @aiAutoDiagnosis.
  ///
  /// In ko, this message translates to:
  /// **'AI 자동 정밀 판독'**
  String get aiAutoDiagnosis;

  /// No description provided for @retakePhoto.
  ///
  /// In ko, this message translates to:
  /// **'벌통 다시 촬영하기'**
  String get retakePhoto;

  /// No description provided for @editHive.
  ///
  /// In ko, this message translates to:
  /// **'수정'**
  String get editHive;

  /// No description provided for @today.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In ko, this message translates to:
  /// **'어제'**
  String get yesterday;

  /// Relative day label for diagnosis history.
  ///
  /// In ko, this message translates to:
  /// **'{count}일 전'**
  String daysAgo(int count);

  /// History row value, e.g. 84점 (위험).
  ///
  /// In ko, this message translates to:
  /// **'{score}점 ({tier})'**
  String scoreWithTier(int score, String tier);

  /// No description provided for @hiveLocationLabel.
  ///
  /// In ko, this message translates to:
  /// **'위치(위도, 경도)'**
  String get hiveLocationLabel;

  /// No description provided for @hiveInstalledAtLabel.
  ///
  /// In ko, this message translates to:
  /// **'설치일'**
  String get hiveInstalledAtLabel;

  /// No description provided for @hiveCreatedAtLabel.
  ///
  /// In ko, this message translates to:
  /// **'등록일'**
  String get hiveCreatedAtLabel;

  /// No description provided for @captureCta.
  ///
  /// In ko, this message translates to:
  /// **'진단하기'**
  String get captureCta;

  /// No description provided for @lastMeasuredAt.
  ///
  /// In ko, this message translates to:
  /// **'최근 측정일'**
  String get lastMeasuredAt;

  /// No description provided for @scoreSuffix.
  ///
  /// In ko, this message translates to:
  /// **'점'**
  String get scoreSuffix;

  /// No description provided for @noAnalysisYet.
  ///
  /// In ko, this message translates to:
  /// **'아직 진단 없음'**
  String get noAnalysisYet;

  /// No description provided for @cardLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'불러오지 못함'**
  String get cardLoadFailed;

  /// No description provided for @upgradeCta.
  ///
  /// In ko, this message translates to:
  /// **'UPGRADE'**
  String get upgradeCta;

  /// No description provided for @badgeSafe.
  ///
  /// In ko, this message translates to:
  /// **'안전 단계'**
  String get badgeSafe;

  /// No description provided for @badgeWatch.
  ///
  /// In ko, this message translates to:
  /// **'주의 단계'**
  String get badgeWatch;

  /// No description provided for @badgeDanger.
  ///
  /// In ko, this message translates to:
  /// **'위험 단계'**
  String get badgeDanger;

  /// No description provided for @badgeUnknown.
  ///
  /// In ko, this message translates to:
  /// **'진단 필요'**
  String get badgeUnknown;

  /// Home free-tier quota banner. count = monthly allowance (remaining not exposed by API).
  ///
  /// In ko, this message translates to:
  /// **'이번 달 무료 진단 {count}회'**
  String quotaBanner(int count);

  /// No description provided for @hiveAnalysesSectionTitle.
  ///
  /// In ko, this message translates to:
  /// **'진단 이력'**
  String get hiveAnalysesSectionTitle;

  /// No description provided for @hiveAnalysesComingSoon.
  ///
  /// In ko, this message translates to:
  /// **'아직 이 벌통의 진단 기록이 없어요'**
  String get hiveAnalysesComingSoon;

  /// No description provided for @errNotFound.
  ///
  /// In ko, this message translates to:
  /// **'요청한 정보를 찾을 수 없어요'**
  String get errNotFound;

  /// No description provided for @errQuota.
  ///
  /// In ko, this message translates to:
  /// **'이번 달 무료 진단 횟수를 모두 사용했어요'**
  String get errQuota;

  /// No description provided for @errAiUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'AI 분석 서비스가 일시적으로 불안정해요. 잠시 후 다시 시도해 주세요'**
  String get errAiUnavailable;

  /// No description provided for @historyTitle.
  ///
  /// In ko, this message translates to:
  /// **'진단 이력'**
  String get historyTitle;

  /// No description provided for @historyEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 진단 기록이 없어요'**
  String get historyEmptyTitle;

  /// No description provided for @historyEmptyBody.
  ///
  /// In ko, this message translates to:
  /// **'벌통을 촬영해 첫 진단을 시작해 보세요'**
  String get historyEmptyBody;

  /// No description provided for @historyErrorTitle.
  ///
  /// In ko, this message translates to:
  /// **'진단 이력을 불러오지 못했어요'**
  String get historyErrorTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settingsTitle;

  /// No description provided for @settingsAccountSection.
  ///
  /// In ko, this message translates to:
  /// **'계정'**
  String get settingsAccountSection;

  /// No description provided for @settingsAppSection.
  ///
  /// In ko, this message translates to:
  /// **'앱 설정'**
  String get settingsAppSection;

  /// No description provided for @settingsPlanSection.
  ///
  /// In ko, this message translates to:
  /// **'구독'**
  String get settingsPlanSection;

  /// No description provided for @profileEditTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로필 편집'**
  String get profileEditTitle;

  /// No description provided for @fieldEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get fieldEmail;

  /// No description provided for @fieldName.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get fieldName;

  /// No description provided for @fieldRole.
  ///
  /// In ko, this message translates to:
  /// **'역할'**
  String get fieldRole;

  /// No description provided for @fieldMemberSince.
  ///
  /// In ko, this message translates to:
  /// **'가입일'**
  String get fieldMemberSince;

  /// No description provided for @roleUser.
  ///
  /// In ko, this message translates to:
  /// **'양봉가'**
  String get roleUser;

  /// No description provided for @roleAdmin.
  ///
  /// In ko, this message translates to:
  /// **'관리자'**
  String get roleAdmin;

  /// No description provided for @themeMode.
  ///
  /// In ko, this message translates to:
  /// **'화면 테마'**
  String get themeMode;

  /// No description provided for @themeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ko, this message translates to:
  /// **'밝게'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ko, this message translates to:
  /// **'어둡게'**
  String get themeDark;

  /// No description provided for @planLabel.
  ///
  /// In ko, this message translates to:
  /// **'요금제'**
  String get planLabel;

  /// No description provided for @planFree.
  ///
  /// In ko, this message translates to:
  /// **'무료'**
  String get planFree;

  /// No description provided for @planBasic.
  ///
  /// In ko, this message translates to:
  /// **'베이직'**
  String get planBasic;

  /// No description provided for @planPro.
  ///
  /// In ko, this message translates to:
  /// **'프로'**
  String get planPro;

  /// No description provided for @quotaRemaining.
  ///
  /// In ko, this message translates to:
  /// **'이번 달 무료 진단'**
  String get quotaRemaining;

  /// Remaining free analyses this month.
  ///
  /// In ko, this message translates to:
  /// **'{count}회'**
  String quotaCount(int count);

  /// No description provided for @quotaUnlimited.
  ///
  /// In ko, this message translates to:
  /// **'무제한'**
  String get quotaUnlimited;

  /// No description provided for @appVersion.
  ///
  /// In ko, this message translates to:
  /// **'앱 버전'**
  String get appVersion;

  /// No description provided for @logoutConfirm.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃할까요?'**
  String get logoutConfirm;

  /// No description provided for @profileSaveComingSoon.
  ///
  /// In ko, this message translates to:
  /// **'프로필 수정은 곧 제공될 예정이에요'**
  String get profileSaveComingSoon;

  /// No description provided for @tierSafe.
  ///
  /// In ko, this message translates to:
  /// **'안전'**
  String get tierSafe;

  /// No description provided for @tierWatch.
  ///
  /// In ko, this message translates to:
  /// **'주의'**
  String get tierWatch;

  /// No description provided for @tierDanger.
  ///
  /// In ko, this message translates to:
  /// **'위험'**
  String get tierDanger;

  /// No description provided for @tierUnknown.
  ///
  /// In ko, this message translates to:
  /// **'진단 필요'**
  String get tierUnknown;
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
