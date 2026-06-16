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
  String get back => '뒤로';
}
