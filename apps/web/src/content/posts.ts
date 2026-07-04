export type Post = {
  slug: string;
  title: string;
  date: string;
  excerpt: string;
  body: string[];
};

/** 블로그 골격 검증용 더미 글. 실제 콘텐츠(MDX 등)로 추후 교체. */
export const posts: Post[] = [
  {
    slug: 'varroa-camera-diagnosis',
    title: '꿀벌 응애, 카메라로 진단하는 시대',
    date: '2026-06-10',
    excerpt: '스마트폰 사진 한 장으로 바로아 응애 감염을 조기에 발견하는 원리와 활용법을 소개합니다.',
    body: [
      '※ 본 글은 블로그 골격 검증용 더미 콘텐츠입니다. 실제 발행 전 교체됩니다.',
      '바로아 응애(Varroa destructor)는 꿀벌 군집에 치명적인 외부 기생충으로, 조기 발견이 피해 최소화의 핵심입니다.',
      'HelpBee는 벌통 사진을 AI로 분석해 응애 감염 위험도를 0~100으로 산출하고, 위험 구간에 맞는 권장 조치를 제시합니다.',
      '현장에서 한 손으로 5초 안에 진단을 받을 수 있도록 설계되었습니다.',
    ],
  },
];

export function getPost(slug: string): Post | undefined {
  return posts.find((p) => p.slug === slug);
}
