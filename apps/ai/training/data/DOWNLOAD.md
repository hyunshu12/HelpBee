# 학습 데이터 다운로드 절차 (Windows 학습 박스)

2-stage 재설계(계획 1)에 쓰는 원본 데이터를 학습 박스(`ssh beetrain`)에 받는 절차다.
원본 데이터는 **git 에 절대 넣지 않는다** — 전부 `HELPBEE_DATA_ROOT` 아래에 둔다.

| 항목 | 값 |
|---|---|
| 데이터 루트 | `HELPBEE_DATA_ROOT=D:\helpbee-data` (Git Bash 에서는 `/d/helpbee-data`) |
| 7-Zip | `C:\Program Files\7-Zip\7z.exe` (Git Bash: `"/c/Program Files/7-Zip/7z.exe"`) |
| 셸 | 명령은 Git Bash 기준. `PYTHONUTF8=1` 이 설정돼 있어야 한다 |

## 0. AI Hub API 키 — 커밋·로그 금지

- 키는 **ssh 세션의 환경변수 `AIHUB_APIKEY` 로만** 넘긴다. aihubshell 이 이 변수를 읽는다
  (`-aihubapikey` 인자를 안 주면 `$AIHUB_APIKEY` 사용).
- 레포 안 파일(`.env` 포함), 셸 rc 파일, 명령줄 인자, 로그에 키를 쓰지 않는다. 명령줄에 치면
  bash history 에 남으니 화면에 안 보이게 읽는다:

```bash
read -rs -p "AI Hub API key: " AIHUB_APIKEY; echo; export AIHUB_APIKEY
```

- 세션이 끝나면 변수도 사라진다. 다음 세션에서 다시 입력한다.
- 키가 커밋되거나 로그에 찍혔으면 AI Hub 에서 즉시 재발급한다.

## 1. aihubshell 받기

```bash
curl -fsSL -o ~/aihubshell https://api.aihub.or.kr/api/aihubshell.do
head -5 ~/aihubshell   # "aihubshell version ..." 이 보여야 한다 (HTML 오류 페이지면 URL 확인)
```

> 계획서의 `https://api.aihub.or.kr/info/aihubshell.sh` 는 2026-09-23 기준 404 를 돌려준다.
> 위 `aihubshell.do` 주소는 같은 날 확인했다 (version 25.09.19 v0.6).

## 2. 파일키·용량 확인 (다운로드 전)

```bash
bash ~/aihubshell -mode l -datasetkey 71667 | tee /d/helpbee-data/aihub-71667-filetree.txt
bash ~/aihubshell -mode l -datasetkey 71488 | tee /d/helpbee-data/aihub-71488-filetree.txt
```

- 71667 에서 Validation 파일키가 `521779`, `521780` 인지, Training 파일키와 용량이 얼마인지 확인한다.
  목록과 다르면 아래 명령의 파일키를 목록 값으로 바꾼다.
- 71488 목록으로 스펙 §5.3 표(파일키·용량)를 갱신한다.
- D: 여유 공간은 받을 용량의 **2배 이상** 필요하다 — aihubshell 이 `download.tar` 를 받은 뒤 같은
  폴더에 풀기 때문에, 해제가 끝날 때까지 tar 와 내용물이 같이 존재한다.

## 3. 71667 Validation 셋

aihubshell 은 **현재 폴더**에 `download.tar` 를 받고 풀어서 part 파일을 합친다. 먼저 대상 폴더로 이동한다.

```bash
mkdir -p /d/helpbee-data/aihub-71667-val && cd /d/helpbee-data/aihub-71667-val
bash ~/aihubshell -mode d -datasetkey 71667 -filekey 521779,521780
```

## 4. 71667 Training 셋 (백그라운드)

용량이 커서 시간이 오래 걸린다. 로그를 파일로 남기고 백그라운드로 돌린다.

```bash
mkdir -p /d/helpbee-data/aihub-71667-train && cd /d/helpbee-data/aihub-71667-train
nohup bash ~/aihubshell -mode d -datasetkey 71667 -filekey <2단계에서 확인한 Training 파일키들> \
  > download.log 2>&1 &
disown
tail -f download.log   # Ctrl+C 로 tail 만 빠져나온다 (다운로드는 계속)
```

- `export AIHUB_APIKEY` 를 한 같은 세션에서 실행해야 키가 넘어간다. 로그에는 키가 찍히지 않는다
  (헤더로만 전송).
- ⚠️ Windows OpenSSH 는 세션을 닫을 때 자식 프로세스를 같이 죽일 수 있다. 첫 실행 뒤 ssh 를 끊었다
  다시 붙어서 `download.log` 가 계속 늘어나는지 확인한다. 멈췄다면 원격 데스크톱 세션의 Git Bash
  창에서 같은 명령을 실행한다. 중단된 경우 같은 폴더에서 다시 실행하면 `curl -C -` 로 이어받는다.

## 5. zip 해제 (7-Zip)

AI Hub 파일은 tar 안에 zip 으로 들어 있다. 한국어 파일명이 깨지지 않게 코드페이지를 지정해 푼다.

```bash
SEVENZ="/c/Program Files/7-Zip/7z.exe"
cd /d/helpbee-data/aihub-71667-val
find . -name '*.zip' -print0 | while IFS= read -r -d '' z; do
  "$SEVENZ" x -mcp=65001 -y "$z" -o"$(dirname "$z")/$(basename "$z" .zip)"
done
# 폴더명 검증 — 0 이면 파일명이 깨진 것. -mcp=949 로 다시 푼다.
test "$(find . -type d -name '01.원천데이터' | wc -l)" -ge 1 && echo OK || echo "FAIL: 01.원천데이터 없음 — 인코딩 확인"
```

Training 폴더(`aihub-71667-train`)도 같은 방식으로 푼다. 다 풀고 검증까지 통과한 뒤에만 zip 을 정리한다.

## 6. 외부 데이터 — VarroaDataset · EV2 (Zenodo, CC BY 4.0)

API 키가 필요 없다. 받은 뒤 **MD5 를 반드시 확인**한다 (값은 Zenodo API 기준, 2026-09-23 확인).

### VarroaDataset (https://zenodo.org/records/4085044) → `D:\helpbee-data\external\varroadataset`

```bash
mkdir -p /d/helpbee-data/external/varroadataset && cd /d/helpbee-data/external/varroadataset
for f in gt.csv train.zip val.zip test.zip; do
  curl -fL -C - -o "$f" "https://zenodo.org/records/4085044/files/$f?download=1"
done
```

| 파일 | 크기 | MD5 |
|---|---|---|
| gt.csv | 1.2 MB | `46889d2689eac833c6eb89a95085b8ef` |
| train.zip | 703 MB | `87cb443aa28650ef34e83b2d1b3fa26d` |
| val.zip | 163 MB | `631318f802b059e5274b0b26c4c0a593` |
| test.zip | 292 MB | `a510921655dae21c10b5389fa0cfeef5` |

`gt.csv` 의 이미지 경로가 `train/…`, `val/…`, `test/…` 로 시작하므로 세 zip 을 이 폴더에 그대로 푼다.
파서: `training.data.external_sources.parse_varroa_gt`.

### EV2 (https://zenodo.org/records/13771384) → `D:\helpbee-data\external\ev2`

```bash
mkdir -p /d/helpbee-data/external/ev2 && cd /d/helpbee-data/external/ev2
curl -fL -C - -o dataset.zip "https://zenodo.org/records/13771384/files/dataset.zip?download=1"
```

MD5 확인 (PowerShell 또는 cmd):

```powershell
certutil -hashfile D:\helpbee-data\external\ev2\dataset.zip MD5
# 기대값: c626a1f198cf7d0f41eae9c2660b0985 (1,084,450,229 bytes)
```

VarroaDataset zip 도 같은 명령으로 확인한다. 일치하면 푼다:

```bash
"/c/Program Files/7-Zip/7z.exe" x -y dataset.zip -o.
ls   # dataset_free/  dataset_infested/  labels.txt
```

파서: `training.data.external_sources.parse_ev2(<ev2>/labels.txt)`. ⚠️ `dataset_free/` 에는 감염됐지만
응애가 안 보이는 프레임 699장이 섞여 있다 — 감염 라벨은 폴더가 아니라 `labels.txt` 의 `video` 접두에서
나온다 (자세한 스키마는 `external_sources.py` docstring).

## 최종 폴더 구조

```
D:\helpbee-data\
├── aihub-71667-filetree.txt
├── aihub-71488-filetree.txt
├── aihub-71667-val\      # …\01.원천데이터\, …\02.라벨링데이터\
├── aihub-71667-train\
└── external\
    ├── varroadataset\    # gt.csv, train\, val\, test\
    └── ev2\              # labels.txt, dataset_free\, dataset_infested\
```
