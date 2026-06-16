// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => 'HelpBee';

  @override
  String get splashTagline => '사진 한 장으로 응애 진단';

  @override
  String get onbTitle1 => '벌 사진 한 장으로 응애 감염 위험을 진단해요';

  @override
  String get onbBody1 => '최첨단 AI가 벌의 상태를 분석하여 응애 감염 여부를 즉시 확인해 드립니다';

  @override
  String get onbTitle2 => '가이드 안에 벌통을 맞추고 찍기만 하면 돼요';

  @override
  String get onbBody2 => '장갑을 낀 상태에서도 편리하게 자동 초점 가이드로 정확하게 촬영하세요';

  @override
  String get onbTitle3 => '분석이 끝나면 알림으로 알려 드릴게요';

  @override
  String get onbBody3 => '현장에서 바쁜 작업을 하시는 동안 HelpBee가 꼼꼼히 분석해 드립니다';

  @override
  String get onbSkip => '건너뛰기';

  @override
  String get onbNext => '다음 단계로';

  @override
  String get onbStart => '시작하기';

  @override
  String get emailLabel => '이메일';

  @override
  String get emailHint => '이메일 주소를 입력하세요';

  @override
  String get passwordLabel => '비밀번호';

  @override
  String get passwordHint => '비밀번호를 입력하세요';

  @override
  String get keepLoggedIn => '로그인 상태 유지';

  @override
  String get loginCta => '로그인하기';

  @override
  String get findId => '아이디 찾기';

  @override
  String get findPassword => '비밀번호 찾기';

  @override
  String get signupLink => '회원가입';

  @override
  String get snsDivider => 'SNS 계정으로 로그인하기';

  @override
  String get comingSoon => '준비 중입니다';

  @override
  String get signupTitle => '회원가입';

  @override
  String get nameLabel => '이름';

  @override
  String get nameHint => '이름을 입력하세요';

  @override
  String get passwordRuleHint => '비밀번호는 10자 이상이에요';

  @override
  String get passwordConfirmLabel => '비밀번호 확인';

  @override
  String get passwordConfirmHint => '비밀번호를 다시 입력하세요';

  @override
  String get passwordMismatch => '비밀번호가 일치하지 않습니다';

  @override
  String get signupCta => '가입하기';

  @override
  String get haveAccount => '이미 계정이 있으신가요?';

  @override
  String get goLogin => '로그인';

  @override
  String get homeTitle => '양봉장 현황';

  @override
  String get homePlaceholderBody => '로그인 완료! 홈 화면은 다음 단계에서 만들어집니다.';

  @override
  String get logout => '로그아웃';

  @override
  String get valEmail => '올바른 이메일 형식이 아니에요';

  @override
  String get valRequired => '필수 입력 항목이에요';

  @override
  String get valPasswordLen => '비밀번호는 10자 이상이어야 해요';

  @override
  String get errInvalidCredentials => '이메일 또는 비밀번호가 올바르지 않아요';

  @override
  String get errAccountLocked => '로그인 시도가 많아 잠시 잠겼어요. 잠시 후 다시 시도해 주세요';

  @override
  String get errEmailTaken => '이미 가입된 이메일이에요';

  @override
  String get errEmailNotVerified => '이메일 인증이 필요해요';

  @override
  String get errRateLimited => '요청이 많아요. 잠시 후 다시 시도해 주세요';

  @override
  String get errNetwork => '인터넷 연결이 약해요. 잠시 후 다시 시도해 주세요';

  @override
  String get errTimeout => '응답이 지연되고 있어요. 다시 시도해 주세요';

  @override
  String get errServer => '일시적인 오류가 발생했어요';

  @override
  String get errValidation => '입력한 정보를 다시 확인해 주세요';

  @override
  String errRetryAfter(int seconds) {
    return '$seconds초 후 다시 시도해 주세요';
  }

  @override
  String get errUnknown => '알 수 없는 오류가 발생했어요';

  @override
  String get showPassword => '비밀번호 표시';

  @override
  String get hidePassword => '비밀번호 숨기기';

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonCancel => '취소';

  @override
  String get commonConfirm => '확인';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonSave => '저장';

  @override
  String get back => '뒤로';

  @override
  String homeGreeting(String name) {
    return '$name님, 안녕하세요';
  }

  @override
  String get navHives => '벌통';

  @override
  String get navHistory => '진단 이력';

  @override
  String get navSettings => '설정';

  @override
  String get addHive => '벌통 등록';

  @override
  String get createHive => '등록하기';

  @override
  String get hivesEmptyTitle => '등록된 벌통이 없어요';

  @override
  String get hivesEmptyBody => '아래 버튼으로 첫 벌통을 등록해 보세요';

  @override
  String get hivesErrorTitle => '벌통을 불러오지 못했어요';

  @override
  String get hiveNameLabel => '벌통 이름';

  @override
  String get hiveNameHint => '예: 1번 벌통';

  @override
  String get hiveAddressLabel => '주소 (선택)';

  @override
  String get hiveAddressHint => '예: 경기도 양평군';

  @override
  String get hiveNoteLabel => '메모 (선택)';

  @override
  String get hiveNoteHint => '특이사항을 적어 두세요';

  @override
  String get hiveCreated => '벌통을 등록했어요';

  @override
  String get hiveDeleted => '벌통을 삭제했어요';

  @override
  String get deleteHive => '벌통 삭제';

  @override
  String get deleteHiveConfirm => '이 벌통을 삭제할까요? 삭제하면 목록에서 사라져요.';

  @override
  String get hiveDetailTitle => '벌통 정보';

  @override
  String get hiveRiskSubtitle => '현재 감염 심각 수준';

  @override
  String get hiveLocationCard => '벌통 위치';

  @override
  String get installDateLabel => '설치날짜';

  @override
  String get statusLabel => '상태';

  @override
  String get memoTitle => '메모';

  @override
  String get historyRecentTitle => '과거 진단 이력 (최신순)';

  @override
  String get seeMore => '더보기';

  @override
  String get aiAutoDiagnosis => 'AI 자동 정밀 판독';

  @override
  String get retakePhoto => '벌통 다시 촬영하기';

  @override
  String get editHive => '수정';

  @override
  String get today => '오늘';

  @override
  String get yesterday => '어제';

  @override
  String daysAgo(int count) {
    return '$count일 전';
  }

  @override
  String scoreWithTier(int score, String tier) {
    return '$score점 ($tier)';
  }

  @override
  String get hiveLocationLabel => '위치(위도, 경도)';

  @override
  String get hiveInstalledAtLabel => '설치일';

  @override
  String get hiveCreatedAtLabel => '등록일';

  @override
  String get captureCta => '진단하기';

  @override
  String get lastMeasuredAt => '최근 측정일';

  @override
  String get scoreSuffix => '점';

  @override
  String get noAnalysisYet => '아직 진단 없음';

  @override
  String get cardLoadFailed => '불러오지 못함';

  @override
  String get upgradeCta => 'UPGRADE';

  @override
  String get badgeSafe => '안전 단계';

  @override
  String get badgeWatch => '주의 단계';

  @override
  String get badgeDanger => '위험 단계';

  @override
  String get badgeUnknown => '진단 필요';

  @override
  String quotaBanner(int count) {
    return '이번 달 무료 진단 $count회';
  }

  @override
  String get hiveAnalysesSectionTitle => '진단 이력';

  @override
  String get hiveAnalysesComingSoon => '아직 이 벌통의 진단 기록이 없어요';

  @override
  String get errNotFound => '요청한 정보를 찾을 수 없어요';

  @override
  String get errQuota => '이번 달 무료 진단 횟수를 모두 사용했어요';

  @override
  String get errAiUnavailable => 'AI 분석 서비스가 일시적으로 불안정해요. 잠시 후 다시 시도해 주세요';

  @override
  String get historyTitle => '진단 이력';

  @override
  String get historyEmptyTitle => '아직 진단 기록이 없어요';

  @override
  String get historyEmptyBody => '벌통을 촬영해 첫 진단을 시작해 보세요';

  @override
  String get historyErrorTitle => '진단 이력을 불러오지 못했어요';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsAccountSection => '계정';

  @override
  String get settingsAppSection => '앱 설정';

  @override
  String get settingsPlanSection => '구독';

  @override
  String get profileEditTitle => '프로필 편집';

  @override
  String get fieldEmail => '이메일';

  @override
  String get fieldName => '이름';

  @override
  String get fieldRole => '역할';

  @override
  String get fieldMemberSince => '가입일';

  @override
  String get roleUser => '양봉가';

  @override
  String get roleAdmin => '관리자';

  @override
  String get themeMode => '화면 테마';

  @override
  String get themeSystem => '시스템 설정';

  @override
  String get themeLight => '밝게';

  @override
  String get themeDark => '어둡게';

  @override
  String get planLabel => '요금제';

  @override
  String get planFree => '무료';

  @override
  String get planBasic => '베이직';

  @override
  String get planPro => '프로';

  @override
  String get quotaRemaining => '이번 달 무료 진단';

  @override
  String quotaCount(int count) {
    return '$count회';
  }

  @override
  String get quotaUnlimited => '무제한';

  @override
  String get appVersion => '앱 버전';

  @override
  String get logoutConfirm => '로그아웃할까요?';

  @override
  String get profileSaveComingSoon => '프로필 수정은 곧 제공될 예정이에요';

  @override
  String get tierSafe => '안전';

  @override
  String get tierWatch => '주의';

  @override
  String get tierDanger => '위험';

  @override
  String get tierUnknown => '진단 필요';

  @override
  String get captureGuide => '가이드 안에 벌통을 맞추고 흔들리지 않게\n찍어주세요';

  @override
  String get captureNoCamera => '시뮬레이터에는 카메라가 없어요.\n갤러리에서 사진을 선택해 주세요';

  @override
  String get captureCameraRetry => '카메라를 열 수 없어요. 화면을 탭해 다시 시도하거나 갤러리를 사용해 주세요';

  @override
  String get captureGallery => '갤러리';

  @override
  String get captureFlash => '플래시';

  @override
  String get captureFlashOff => '플래시 꺼짐';

  @override
  String get captureFlashAuto => '플래시 자동';

  @override
  String get captureFlashOn => '플래시 켜짐';

  @override
  String get captureShutterA11y => '촬영';

  @override
  String get captureCloseA11y => '닫기';

  @override
  String get reviewTitle => '벌통 프레임이 선명한가요?';

  @override
  String get reviewBody => '정확한 분석을 위해 벌집과 벌이 선명하게\n보이도록 찍어주세요';

  @override
  String get reviewAnalyzeCta => '이 사진으로 분석하기';

  @override
  String get reviewRetake => '다시 찍기';

  @override
  String get analyzingTitle => '벌통을 분석하고 있어요';

  @override
  String get analyzingBody => 'AI 모델이 소비판 내부의 진드기를\n정밀 카운팅하고 있습니다.\n약 3초 소요됩니다';

  @override
  String get analyzingFailedTitle => '분석을 완료하지 못했어요';

  @override
  String get reportTitle => '진단 결과 레포트';

  @override
  String get reportRiskStageTitle => '응애 감염 위험 단계';

  @override
  String get reportAnalyzedPhoto => '분석된 사진';

  @override
  String get reportRecommendTitle => '권장 조치';

  @override
  String get reportRecommendDisclaimer =>
      '※ AI 처방이 아닌 일반 안내예요. 정확한 처방은 전문가와 상담하세요';

  @override
  String get reportHome => '홈으로';

  @override
  String get reportSaveToHistory => '상세 이력에 기록';

  @override
  String get reportSavedSnack => '진단이 이력에 기록되었어요';

  @override
  String get reportShareA11y => '공유';

  @override
  String get gaugeCaptionSafe => '양호 수준';

  @override
  String get gaugeCaptionWatch => '주의 수준';

  @override
  String get gaugeCaptionDanger => '심각 수준';

  @override
  String get gaugeCaptionUnknown => '측정 불가';

  @override
  String get recSafe1 => '현재 응애 위험은 낮아요. 정기 점검을 유지하세요';

  @override
  String get recSafe2 => '2~4주 간격으로 재진단을 권장해요';

  @override
  String get recWatch1 => '1~2주 내 재촬영으로 추세를 확인하세요';

  @override
  String get recWatch2 => '천연 응애 예방제(개미산 등) 사용을 검토하세요';

  @override
  String get recWatch3 => '인접 벌통도 함께 관찰하세요';

  @override
  String get recDanger1 => '해당 벌통을 즉시 외부와 분리 격리하세요';

  @override
  String get recDanger2 => '친환경 응애 약제 처방이 긴급히 요구됩니다';

  @override
  String get recDanger3 => '반경 5미터 내 모든 벌통을 점검하세요';

  @override
  String get recDanger4 => '7일 후 추적 진단을 예약하세요';

  @override
  String get pickHiveTitle => '촬영할 벌통 선택';

  @override
  String get pickHiveEmpty => '먼저 벌통을 등록해 주세요';

  @override
  String get am => '오전';

  @override
  String get pm => '오후';

  @override
  String get errImageUnsupported => '지원하지 않는 이미지 형식이에요. JPG·PNG·WEBP만 가능해요';

  @override
  String get errImageTooLarge => '이미지가 너무 커요. 10MB 이하로 다시 시도해 주세요';

  @override
  String get errImageInvalid => '이미지를 읽지 못했어요. 다른 사진으로 다시 시도해 주세요';

  @override
  String get errUploadIncomplete => '업로드가 완료되지 않았어요. 다시 시도해 주세요';

  @override
  String get hiveNamePlaceholder => '벌통의 이름';

  @override
  String get hiveLocationHint => 'GPS 좌표 또는 주소';

  @override
  String get hiveInstalledHint => '벌통 설치 날짜';

  @override
  String get hiveNotePlaceholder => '벌통의 초기 상태, 여왕벌 정보 등을 입력하세요';

  @override
  String get useCurrentLocationA11y => '현재 위치 사용';

  @override
  String get pickDateA11y => '설치일 선택';

  @override
  String get installDateRequired => '설치일을 선택해 주세요';
}
