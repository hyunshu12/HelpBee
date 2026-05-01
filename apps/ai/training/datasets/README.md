# training/datasets

이 폴더 안의 **실제 데이터셋(이미지·라벨 원본)은 git-ignored** 입니다. 절대 커밋하지 마세요.

## 데이터 관리 위치
- **라벨링 / 원본 이미지**: [Roboflow](https://roboflow.com) 프로젝트에서 관리
  - cross-labeling, IoU≥0.7 합의, 버전 관리 모두 Roboflow에서 수행
  - 학습 직전 `roboflow download` 또는 export ZIP으로 본 폴더에 펼친다
- **학습된 가중치(weights)**: AWS S3 `helpbee-models` 버킷
  - 경로 컨벤션: `s3://helpbee-models/yolo/v{MAJOR}.{MINOR}.{PATCH}/best.pt`
  - 환경변수 `YOLO_MODEL_VERSION` 으로 추론 서버 부팅 시 다운로드

## 디렉토리 구조 (YOLO 포맷)
```
training/datasets/
└── varroa-v{N}/
    ├── images/
    │   ├── train/      # *.jpg
    │   └── val/        # *.jpg
    ├── labels/
    │   ├── train/      # *.txt  (class cx cy w h, normalized)
    │   └── val/        # *.txt
    └── data.yaml       # path / train / val / nc / names
```

## data.yaml 예시
```yaml
path: ./varroa-v1
train: images/train
val: images/val
nc: 1
names: ['varroa_mite']
```

## Golden holdout
- 100장의 검증 전용 셋(`golden/`)은 학습/aug 에 절대 포함하지 않는다
- 모델 버전 비교 시 동일 golden 셋으로 mAP/recall 측정
