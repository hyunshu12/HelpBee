# 학습 데이터 다운로드 절차 (Windows 학습 박스)

2-stage 재설계(계획 1)에 쓰는 원본 데이터를 학습 박스(`ssh beetrain`)에 받는 절차다.
2026-09-23~24 에 박스에서 실제로 돌리며 막힌 곳을 반영해 다시 썼다. 원본 데이터는 **git 에 절대 넣지
않는다** — 전부 `HELPBEE_DATA_ROOT` 아래에 둔다.

| 항목 | 값 |
|---|---|
| 데이터 루트 | `HELPBEE_DATA_ROOT=D:\helpbee-data` (Git Bash 에서는 `/d/helpbee-data`) |
| D: 용량 | 443 GB (예산은 §2) |
| 7-Zip | `C:\Program Files\7-Zip\7z.exe` (Git Bash: `"/c/Program Files/7-Zip/7z.exe"`) |
| 셸 | 명령은 Git Bash 기준. `PYTHONUTF8=1` 필요. Python 은 **`python`** (`python3` 는 MS Store 스텁으로 간다) |

> ### ⚠️ 지난번에 막힌 것 (2026-09-23/24)
> 1. **`aihubshell -mode d` 로 큰 볼륨을 받으면 디스크가 3배 든다.** CWD 에 `download.tar` 를 받고 →
>    `tar -xvf` 로 part 파일을 풀고 → `cat` 으로 합친다. tar·part·합친 파일이 동시에 존재한다.
>    2배로 잡았다가 `No space left on device` 로 죽었다.
> 2. **AI Hub 서버가 100 GiB part 세트를 한 응답에 두 번 보냈다.** tar 안에 part 0–99 뒤에 0–99 가
>    또 들어 있었다(214 GB). aihubshell 의 병합을 그대로 썼다면 깨진 파일이 나왔다.
>    → 큰 볼륨은 §5 의 **curl 스트리밍 병합 + 정확한 바이트 수 자르기**로 받는다.
> 3. **ssh 세션에서 띄운 프로세스는 세션이 끝나면 죽는다** (`nohup`·`disown` 도 소용없음).
>    `schtasks /run` 도 ssh 에서는 믿을 수 없었다. → §4 처럼 **시간 트리거 schtasks** 로 돌린다.
> 4. **한글이 든 `.ps1` 을 BOM 없는 UTF-8 로 저장하면** PowerShell 5 가 cp949 로 읽다가 파싱에 실패한다.
>    작업은 `LastTaskResult 1` 로 끝나고 로그는 한 줄도 없다. → `.ps1` 은 **UTF-8 with BOM**.
> 5. PowerShell 의 `*>>` 는 로그를 **UTF-16** 으로 붙인다. `cat`/`tail` 로는 깨져 보인다 →
>    `Get-Content -Encoding Unicode` 로 읽거나, 리다이렉트를 bash 안에서 한다(§4 예시).
> 6. 7z 에 `-sccUTF-8` 을 안 주면 콘솔 출력이 cp949 라 한글 멤버명 매칭이 깨진다.
> 7. 라벨 `TL.zip` 을 통째로 풀면 **≈620 GB** 다. 풀지 않는다(§7).

## 0. AI Hub API 키 — 커밋·로그 금지

- 파일 목록(`-mode l`)은 키 없이 된다. **다운로드에만** 키가 필요하다. 키는 환경변수 `AIHUB_APIKEY`
  로만 넘긴다 (aihubshell 도, §5 의 curl 도 이 변수를 쓴다).
- 레포 안 파일(`.env` 포함), 셸 rc, 명령줄 인자, 로그에 키를 쓰지 않는다. 평문 키 파일도 만들지 않는다.
- 대화형 세션에서 잠깐 쓸 때는 화면에 안 보이게 읽는다:

```bash
read -rs -p "AI Hub API key: " AIHUB_APIKEY; echo; export AIHUB_APIKEY
```

- **예약 작업(schtasks)에서 쓸 때**: 키를 DPAPI 로 암호화해 사용자 프로필에 두고, 작업 스크립트 안에서만
  복호화한다. DPAPI 암호문은 **같은 Windows 사용자·같은 머신**에서만 풀린다 (박스: `C:\Users\mso\.aihub_key`).

```powershell
# 1회: 저장 (PowerShell, 박스 사용자 mso 로 로그인한 상태)
Read-Host -AsSecureString "AI Hub API key" | ConvertFrom-SecureString |
  Set-Content -Encoding ascii C:\Users\mso\.aihub_key

# 작업 스크립트 안: 복호화 → 이 프로세스(와 자식)의 환경변수로만
$s = Get-Content C:\Users\mso\.aihub_key | ConvertTo-SecureString
$env:AIHUB_APIKEY = [System.Net.NetworkCredential]::new('', $s).Password
```

- 승인 기간이 끝나면 다운로드가 **HTTP 502** 와 함께 `승인 유효기간 만료 … 재신청` 메시지를 돌려준다
  (본문이 HTML/텍스트라 tar 가 "not a tar archive" 로 죽는다). aihub.or.kr 에서 데이터셋을 재신청한다.
- 키가 커밋되거나 로그에 찍혔으면 AI Hub 에서 즉시 재발급한다.

## 1. aihubshell 받기 (목록 확인용)

```bash
curl -fsSL -o ~/aihubshell https://api.aihub.or.kr/api/aihubshell.do
head -5 ~/aihubshell   # "aihubshell version ..." 이 보여야 한다 (HTML 오류 페이지면 URL 확인)
```

> `https://api.aihub.or.kr/info/aihubshell.sh` 는 2026-09-23 기준 404 다. 위 `aihubshell.do` 는 같은 날
> 확인했다 (version 25.09.19 v0.6).

```bash
bash ~/aihubshell -mode l -datasetkey 71667 | tee /d/helpbee-data/aihub-71667-filetree.txt
bash ~/aihubshell -mode l -datasetkey 71488 | tee /d/helpbee-data/aihub-71488-filetree.txt
```

71667 파일키 (2026-09-24 확인 — 목록과 다르면 목록 값을 쓴다):

| 구분 | 파일 | 파일키 | 정확한 크기 (bytes) |
|---|---|---|---|
| Validation 원천 | VS.zip | 521779 | 27,639,170,144 |
| Validation 라벨 | VL.zip | 521780 | 2,033,900,249 |
| Training 원천 (볼륨 1) | TS.z01 | 521775 | 107,374,182,400 (100 × 1 GiB) |
| Training 원천 (볼륨 2) | TS.z02 | 521776 | 107,374,182,400 (100 × 1 GiB) |
| Training 원천 (마지막 볼륨) | TS.zip | 521777 | 6,574,307,262 |
| Training 라벨 | TL.zip | 521778 | 16,333,884,368 |
| Sublabel | — | 549726 | (계획 1 에서 안 씀) |

## 2. 디스크 예산 (D: 443 GB)

| 단계 | 쓰는 것 | 크기 | 비고 |
|---|---|---|---|
| Validation zip | VS.zip + VL.zip | 29.7 GB | 풀고 검증 끝나면 삭제 |
| Validation 해제본 | `aihub-71667-val/` | ≈ 90 GB | VL 라벨이 2 GB → **62 GB** 로 불어난다 (JSON 1개 ≈ 2 MB, `environment` 센서 시계열) |
| Training 볼륨 | TS.z01 + TS.z02 + TS.zip | 221 GB | 서브셋 검증 후 삭제 |
| Training 라벨 | TL.zip | 16.3 GB | **풀지 않는다**. 서브셋 검증 후 삭제 가능 |
| Training 서브셋 | `aihub-71667-train-sub/` | ≈ 26 GB | 25k 장 |
| **동시 최대** | val 해제본 + 볼륨 + TL + 서브셋 | **≈ 353 GB** | val zip 을 먼저 지운 경우 |

- §5 스트리밍 병합은 **출력 파일 크기만** 쓴다. aihubshell 로 100 GiB 볼륨을 받으면 그 볼륨만 ≈ 300 GB 가
  필요해 위 예산으로는 불가능하다.
- 순서: Validation 받기·풀기·검증 → val zip 삭제 → Training 볼륨 → 서브셋 → 서브셋 검증 → 볼륨 삭제.
- 삭제는 `python tasks.py trash <path>` (또는 휴지통) — 검증 전에 지우지 않는다.

## 3. 받는 방법 고르기

| 파일 | 방법 |
|---|---|
| TS.z01, TS.z02 (각 100 GiB) | **§5 curl 스트리밍 병합 (필수)** |
| TS.zip, TL.zip, VS.zip, VL.zip | §5 를 권장 (같은 스크립트, 크기만 다름). 여유가 3배 이상이면 aihubshell 도 가능 |

aihubshell 을 쓸 때는 CWD 에 `download.tar` 가 생기고 3배 공간이 필요하다는 점만 기억한다:

```bash
mkdir -p /d/helpbee-data/aihub-71667-val && cd /d/helpbee-data/aihub-71667-val
bash ~/aihubshell -mode d -datasetkey 71667 -filekey 521779,521780
# 끝나면 합쳐진 zip 크기를 §1 표와 비교한다 (서버 중복 전송이면 크기가 맞지 않는다)
```

## 4. 오래 걸리는 작업은 schtasks 로

ssh 세션에서 띄운 다운로드·해제는 세션이 끝날 때 같이 죽는다. **1~2분 뒤로 시간 트리거를 건 일회성
예약 작업**으로 돌린다 (`schtasks /run` 은 ssh 에서 믿을 수 없었다).

작업 스크립트는 레포 밖에 둔다 (예: `C:\helpbee\jobs\`). `.ps1` 은 **UTF-8 with BOM** 으로 저장한다
(VS Code: "Save with Encoding → UTF-8 with BOM"; Git Bash: `printf '\xEF\xBB\xBF' | cat - x.ps1 > y.ps1`).

`C:\helpbee\jobs\dl_ts_z01.ps1` 예시:

```powershell
$ErrorActionPreference = 'Stop'
$s = Get-Content C:\Users\mso\.aihub_key | ConvertTo-SecureString
$env:AIHUB_APIKEY = [System.Net.NetworkCredential]::new('', $s).Password
# 로그 리다이렉트는 bash 안에서 → UTF-8 로그 (PowerShell *>> 는 UTF-16)
& 'C:\Program Files\Git\bin\bash.exe' -lc '/c/helpbee/jobs/dl_vol.sh 521775 107374182400 /d/helpbee-data/aihub-71667-train/vols/TS.z01 >> /d/helpbee-data/aihub-71667-train/dl_TS.z01.log 2>&1'
exit $LASTEXITCODE
```

등록·확인 (Git Bash 에서는 `MSYS_NO_PATHCONV=1` 을 붙여야 `/tn` 같은 인자가 경로로 바뀌지 않는다):

```bash
export MSYS_NO_PATHCONV=1
ST=$(date -d '+2 min' +%H:%M)
schtasks /create /tn helpbee-dl-TS.z01 /sc once /st "$ST" /f \
  /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\helpbee\jobs\dl_ts_z01.ps1"
schtasks /query /tn helpbee-dl-TS.z01 /v /fo list | grep -Ei "status|last result|last run"
tail -f /d/helpbee-data/aihub-71667-train/dl_TS.z01.log
```

- `Last Result: 1` 인데 로그가 비어 있으면 거의 항상 `.ps1` 인코딩(BOM 없음) 문제다.
- 작업은 등록한 사용자(mso)로 돈다 — DPAPI 키가 그래야 풀린다.
- PowerShell `*>>` 로 남긴 로그는 `Get-Content -Encoding Unicode <log>` 로 읽는다.

## 5. curl 스트리밍 병합 (권장 다운로드)

aihubshell 이 내부에서 부르는 것과 같은 요청을 curl 로 보내되, tar 를 디스크에 두지 않고 part 를 순서대로
stdout 으로 이어 붙인 뒤 **정확한 바이트 수에서 자른다**.

```bash
curl -L -H "apikey:$AIHUB_APIKEY" "https://api.aihub.or.kr/down/0.6/71667.do?fileSn=<파일키>" \
  | tar -xO | head -c <정확한 bytes> > TS.z01
```

- 요청 하나 = 파일키 하나라 tar 안에는 그 파일의 part(1 GiB 단위)만 순서대로 있다. `tar -xO` 가 이어 붙인다.
- `head -c` 는 **서버 중복 전송 방어**다. 첫 사본만큼 쓰고 파이프를 닫으면 tar·curl 도 멈춘다
  (이때 curl `(23)` / tar `broken pipe` 메시지는 정상).
- 피크 디스크 = 출력 파일 크기뿐. 이어받기(`-C -`)는 안 된다 — 끊기면 그 파일을 처음부터 다시 받는다.

`C:\helpbee\jobs\dl_vol.sh` (크기 검증 포함, 레포 밖):

```bash
#!/usr/bin/env bash
# usage: dl_vol.sh <fileSn> <exact_bytes> <out_path>
set -eu            # pipefail 은 쓰지 않는다: head 가 파이프를 닫으면 curl/tar 가 0 이 아닌 코드로 끝난다
sn=$1; bytes=$2; out=$3
: "${AIHUB_APIKEY:?AIHUB_APIKEY 미설정}"
mkdir -p "$(dirname "$out")"
echo "[$(date '+%F %T')] start fileSn=$sn -> $out"
curl -sS -L -H "apikey:$AIHUB_APIKEY" "https://api.aihub.or.kr/down/0.6/71667.do?fileSn=$sn" \
  | tar -xO | head -c "$bytes" > "$out.partial"
got=$(stat -c %s "$out.partial")
if [ "$got" != "$bytes" ]; then
  echo "SIZE MISMATCH: got $got expected $bytes (502 승인만료? 네트워크 끊김?)"; exit 2
fi
mv "$out.partial" "$out"
echo "[$(date '+%F %T')] OK $out ($got bytes)"
```

크기가 안 맞으면 서버 응답을 직접 본다: `curl -sS -L -H "apikey:$AIHUB_APIKEY" "<URL>" | head -c 600`.

### 볼륨 무결성 확인

TS 3개 볼륨은 **한 폴더**에 있어야 7z 가 첫 볼륨(`TS.zip`)으로 전체를 연다. 박스에서는
`D:\helpbee-data\aihub-71667-train\vols\` 로 옮겼다 (NTFS 심볼릭 링크도 된다).

```bash
cd /d/helpbee-data/aihub-71667-train/vols
ls -l TS.z01 TS.z02 TS.zip          # §1 표의 크기와 바이트 단위로 일치해야 한다
"/c/Program Files/7-Zip/7z.exe" t -mcp=65001 -sccUTF-8 TS.zip | tail -5   # "Everything is Ok"
"/c/Program Files/7-Zip/7z.exe" t -mcp=65001 -sccUTF-8 ../TL.zip | tail -5
```

2026-09-24 실측: TS 249,817 파일 (해제 시 229 GB), TL 249,817 파일 (해제 시 500 GB) — 둘 다 `7z t` 통과.

## 6. Validation 풀기 (7-Zip)

VS.zip·VL.zip·TS·TL 멤버에는 `01.원천데이터/`·`02.라벨링데이터/` 접두가 **없다** (`성충/…`, `유충/…` 로
시작). 그래서 zip 마다 **이름 붙은 폴더를 지정해** 푼다. 코드(`make_split_manifest`, `aihub_to_yolo`,
`make_crops`)는 라벨 경로의 `02.라벨링데이터` 한 세그먼트만 `01.원천데이터` 로 바꿔 이미지를 찾으므로,
두 폴더가 같은 루트 아래 형제여야 한다.

```
<ROOT>/                        ← --roots 로 넘기는 경로 (= /d/helpbee-data/aihub-71667-val)
├── 01.원천데이터/성충/성충_응애/044/X.jpg
└── 02.라벨링데이터/성충/성충_응애/044/X.json    ← 01 아래와 같은 하위 경로
```

```bash
SEVENZ="/c/Program Files/7-Zip/7z.exe"
ROOT=/d/helpbee-data/aihub-71667-val
cd "$ROOT"
# 먼저 목록으로 접두가 없는지 확인 (성충/… 로 시작해야 한다)
"$SEVENZ" l -mcp=65001 -sccUTF-8 VS.zip | sed -n '15,25p'
"$SEVENZ" x -mcp=65001 -sccUTF-8 -y -o"$ROOT/01.원천데이터"  VS.zip
"$SEVENZ" x -mcp=65001 -sccUTF-8 -y -o"$ROOT/02.라벨링데이터" VL.zip
```

- 코드페이지 `-mcp=65001` 이 맞다 (박스에서 확인). 한글 폴더명이 깨지면 해제본을 지우고 다시 푼다.
- 해제는 VL 이 62 GB 로 불어나 오래 걸린다 → §4 처럼 schtasks 로 돌린다.

검증:

```bash
test -d "$ROOT/01.원천데이터/성충" && test -d "$ROOT/02.라벨링데이터/성충" && echo "OK: 형제 레이아웃" \
  || echo "FAIL: $ROOT/01.원천데이터 · $ROOT/02.라벨링데이터 가 둘 다 있어야 함"
# 라벨 대비 이미지 누락 수. make_split_manifest/aihub_to_yolo 도 같은 수를 출력하고 5% 초과면 rc 2.
cd /c/path/to/apps/ai && python -c "from pathlib import Path; from training.data.aihub_to_yolo import collect_samples; collect_samples(Path(r'$ROOT'), mapping='adult1')"
```

검증이 통과한 뒤에만 VS.zip·VL.zip 을 지운다.

## 7. Training 서브셋 (TL.zip 을 풀지 않는다)

Training 은 풀지 않는다. 라벨 `TL.zip`(16.3 GB)은 풀면 **≈620 GB** 다 — JSON 1개가 ≈2 MB 인데 그중
≈1.36 MB 가 `environment` 센서 시계열이다. `training/data/aihub_subset.py` 로 **zip 안에서 스트리밍**해
필요한 필드만 뽑고, 고른 ~25k 장만 최소 JSON + 이미지로 만든다. 박스 실측: index 25분 + materialize 3분.

- 이미지는 §5 의 `vols/TS.zip` (+ `TS.z01`/`TS.z02` 같은 폴더).
- 선택 규칙: 성충 응애 이미지(`has_varroa_adult`) **전부** + 나머지 성충 이미지를 colony 층화로 채움
  (colony 당 총량 ≤ `n × 0.15`), 유충 전용 이미지는 제외. seed 고정이라 재실행 결과가 같다.
  colony 수가 적으면 cap 에 막혀 `n` 에 못 미칠 수 있다 — `select` 가 WARN 을 찍는다.
- 결과 트리는 Validation 과 같은 구조 (`<ROOT>/02.라벨링데이터/성충/성충_응애/NNN/x.json` + `01.원천데이터/...x.jpg`).
  최소 JSON 에는 `categories`·`image{width,height,filename}`·`annotations{category_id,bbox,area}`·
  `collection{device,datetime}`·`colony{id}` 만 있다 (`environment`·`state`·`symptoms` 등 제거).

한 번에 (index → select → materialize, 중간 산출물은 `<out-root>/_subset/`, schtasks 로 돌린다):

```bash
cd /c/path/to/apps/ai
python tasks.py subset \
  --tl-zip /d/helpbee-data/aihub-71667-train/TL.zip \
  --ts-zip /d/helpbee-data/aihub-71667-train/vols/TS.zip \
  --out-root /d/helpbee-data/aihub-71667-train-sub \
  --n 25000 --verify-listing
# --dry 로 명령만 확인할 수 있다. index.jsonl 이 이미 있으면 재사용한다(--reindex 로 다시 생성).
```

단계별로:

```bash
M="python -m training.data.aihub_subset"
W=/d/helpbee-data/aihub-71667-train-sub/_subset
$M index --tl-zip <TL.zip> --out $W/index.jsonl            # 312k 멤버 스트리밍, ≈25분. --limit 2000 으로 먼저 시험
$M select --index $W/index.jsonl --n 25000 --out $W/selected.jsonl
$M materialize --selected $W/selected.jsonl --ts-zip <vols/TS.zip> \
  --out-root /d/helpbee-data/aihub-71667-train-sub \
  --sevenzip "/c/Program Files/7-Zip/7z.exe" --verify-listing
```

- `index` 는 `index.jsonl.part` 에 쓰고 끝나야 rename 한다 — 중간에 끊기면 처음부터 다시 돈다.
  출력의 `n_fail` 이 0 이 아니면 stderr 의 `[index] FAIL` 줄을 확인한다.
- `--verify-listing` 은 7z 로 TS 목록(312k 줄)을 읽어 고른 이미지가 모두 있는지 먼저 본다. 빠지면 rc 2.
- 7z 호출은 `-mcp=65001 -scsUTF-8 -sccUTF-8` (멤버명 코드페이지·UTF-8 listfile·UTF-8 콘솔 출력 — 코드에
  들어 있다). 라벨 수와 추출된 이미지 수가 다르면 rc 2.
- 멤버명에 UTF-8 플래그가 없는 zip 도 처리한다 (cp437 로 읽힌 이름을 원 바이트 → UTF-8/cp949 로 복원).

다음 단계 — 기존 파이프라인이 그대로 읽는다:

```bash
python -m training.data.make_split_manifest \
  --roots /d/helpbee-data/aihub-71667-val /d/helpbee-data/aihub-71667-train-sub \
  --tags 71667-val 71667-train --refreeze          # 재동결은 이번 한 번만 허용
python -m training.data.aihub_to_yolo --source /d/helpbee-data/aihub-71667-train-sub \
  --output <기존 bee-adult1 output> --mapping adult1 --manifest
```

서브셋으로 학습 데이터가 만들어진 걸 확인한 뒤 `vols/` (221 GB) 를 지운다. TL.zip 은 재선택이 필요할 수
있으니 공간이 허락하면 남겨 둔다.

## 8. 외부 데이터 — VarroaDataset · EV2 (Zenodo, CC BY 4.0)

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
├── aihub-71667-val\      # 01.원천데이터\ + 02.라벨링데이터\ 바로 아래 형제 (§6, zip 은 검증 후 삭제)
├── aihub-71667-train\    # TL.zip + vols\TS.zip·TS.z01·TS.z02 (풀지 않음, 서브셋 검증 후 vols 삭제) + dl_*.log
├── aihub-71667-train-sub\  # §7 서브셋: 01.원천데이터\ + 02.라벨링데이터\ (+ _subset\ 중간 산출물)
└── external\
    ├── varroadataset\    # gt.csv, train\, val\, test\
    └── ev2\              # labels.txt, dataset_free\, dataset_infested\
```
